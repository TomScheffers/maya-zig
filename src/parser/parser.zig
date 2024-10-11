const std = @import("std");
const tokenize = @import("tokenize.zig");
const Token = tokenize.Token;
const TokenType = tokenize.TokenType;

const ParserErrors = error{ UnexpectedEOF, UnexpectedToken, ExpectedName, OutOfMemory };

const SqlExpr: type = union {
    StringLiteral: []const u8,
    NumericLiteral: []const u8,
    Identifier: []const u8,
    NamedIdentifier: struct { table: []const u8, name: []const u8 },
    Wildcard: void,
    NamedWildcard: []const u8,
    BinaryExpression: void,
    UnaryExpression: void,
};

const SqlNamedExpr = struct {
    expr: SqlExpr,
    name: ?[]const u8,

    pub fn fromSqlExpr(expr: SqlExpr) SqlNamedExpr {
        return SqlNamedExpr{ .expr = expr, .name = null };
    }
};

const SqlSource: type = union {
    Table: SqlTable,
    Frame: *const SqlFrame,
};

const SqlTable: type = struct { database: ?[]u8, schema: ?[]u8, name: []u8, alias: ?[]u8 };

const SqlJoinMethod: type = enum { LEFT, RIGHT, INNER };

const SqlJoinFrame: type = struct { right: SqlSource, method: SqlJoinMethod, using: std.ArrayList(SqlExpr) };

const SqlFrame: type = struct {
    selections: std.ArrayList(SqlNamedExpr), // SELECT ...
    source: SqlSource, // FROM ...
    // joins: ?std.ArrayList(SqlJoinFrame), // {} JOIN ...
    // where: ?SqlExpr, // WHERE ...
    // group_by: ?std.ArrayList(SqlExpr), // GROUP BY ...
    // having: ?SqlExpr, // HAVING ...
};

const SqlParser = struct {
    tokens: []Token,
    position: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) SqlParser {
        return SqlParser{ .allocator = allocator, .tokens = tokens, .position = 0 };
    }

    fn next(self: *SqlParser) ?Token {
        if (self.position < self.tokens.len) {
            const token = self.tokens[self.position];
            self.position += 1;
            return token;
        }
        return null;
    }

    fn peek(self: *SqlParser) ?Token {
        if (self.position < self.tokens.len) {
            return self.tokens[self.position];
        }
        return null;
    }

    fn expect(self: *SqlParser, expected_type: tokenize.TokenType) ParserErrors!void {
        const token = self.next() orelse return error.UnexpectedEOF;
        if (token.token_type != expected_type) {
            return error.UnexpectedToken;
        }
    }

    fn parseFrame(self: *SqlParser) ParserErrors!SqlFrame {
        const frame = SqlFrame{
            .selections = try self.parseSelections(),
            .source = try self.parseSource(),
            // .joins = try self.parseJoin(),
            //.where = try self.parseWhere(),
            // .group_by = group_by,
            // .having = having_clause,
        };
        // TODO: Skip ) and read alias if subquery
        return frame;
    }

    fn parseSelections(self: *SqlParser) ParserErrors!std.ArrayList(SqlNamedExpr) {
        try self.expect(tokenize.TokenType.Keyword); // Expect "SELECT"

        var selections = std.ArrayList(SqlNamedExpr).init(self.allocator);
        outer: while (true) {
            var selection: ?SqlNamedExpr = null;

            while (true) {
                const token = self.peek() orelse break;

                // Check if we need to terminate for FROM
                if ((token.token_type == TokenType.Keyword) and std.mem.eql(u8, token.value, "FROM")) {
                    if (selection) |s| {
                        try selections.append(s);
                    }
                    break :outer;
                }

                switch (token.token_type) {
                    .Keyword => {
                        if (std.mem.eql(u8, token.value, "as")) {
                            const name = try (self.peek() orelse error.ExpectedName);
                            if (name.token_type == TokenType.Identifier) {
                                const alias = try self.allocator.dupe(u8, name.value);
                                selection.?.name = alias;
                            } else {
                                return error.ExpectedName;
                            }
                        }

                        std.debug.print("\nPlease implement {s}", .{token.value});
                    },
                    .Symbol => {
                        if (token.value[0] == ',') {
                            self.position += 1;
                            break;
                        } else if ((selection == null) and (token.value[0] == '*')) {
                            selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .Wildcard = undefined });
                        }
                    },
                    .Identifier => {
                        const pidx = std.mem.indexOf(u8, token.value, ".");
                        if (std.mem.containsAtLeast(u8, token.value, 1, "*")) {
                            // Wilcard
                            if (pidx) |idx| {
                                const lit = try self.allocator.dupe(u8, token.value[0..idx]);
                                selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .NamedWildcard = lit });
                            } else {
                                selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .Wildcard = undefined });
                            }
                        } else {
                            // Column identifiers
                            if (pidx) |idx| {
                                const tbl = try self.allocator.dupe(u8, token.value[0..idx]);
                                const idnt = try self.allocator.dupe(u8, token.value[idx..]);
                                selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .NamedIdentifier = .{ .table = tbl, .name = idnt } });
                            } else {
                                const idnt = try self.allocator.dupe(u8, token.value);
                                selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .Identifier = idnt });
                            }
                        }
                    },
                    .NumericLiteral => {
                        const lit = try self.allocator.dupe(u8, token.value);
                        selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .NumericLiteral = lit });
                    },
                    .StringLiteral => {
                        const lit = try self.allocator.dupe(u8, token.value);
                        selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .StringLiteral = lit });
                    },
                    else => {
                        std.debug.print("\nPlease implement {}", .{token});
                    },
                }

                self.position += 1;
            }

            if (selection) |s| {
                try selections.append(s);
            }
        }

        return selections;
    }

    fn parseSource(self: *SqlParser) ParserErrors!SqlSource {
        try self.expect(tokenize.TokenType.Keyword); // Expect "FROM"

        const token = self.next().?;

        if ((token.token_type == TokenType.Symbol) and (token.value[0] == '(')) {
            // Subquery
            self.position += 1;
            const frame = try self.parseFrame();
            return SqlSource{ .Frame = &frame };
        } else {
            // Find name of table
            var database: ?[]u8 = null;
            var schema: ?[]u8 = null;
            var name: []u8 = "";
            var alias: ?[]u8 = null;

            const fi = std.mem.indexOf(u8, token.value, ".");
            const li = std.mem.lastIndexOf(u8, token.value, ".");
            if (fi) |i| {
                if (li.? == i) {
                    schema = try self.allocator.dupe(u8, token.value[0..i]);
                    name = try self.allocator.dupe(u8, token.value[i + 1 ..]);
                } else {
                    database = try self.allocator.dupe(u8, token.value[0..i]);
                    schema = try self.allocator.dupe(u8, token.value[i + 1 .. li.?]);
                    name = try self.allocator.dupe(u8, token.value[li.? + 1 ..]);
                }
            } else {
                name = try self.allocator.dupe(u8, token.value);
            }

            // Find alias if available
            const aso = self.peek();
            if (aso) |as| {
                if ((as.token_type == TokenType.Identifier) and (std.mem.eql(u8, as.value, "as"))) {
                    self.position += 1;
                    const al = self.next().?;
                    std.debug.print("As name: {s}", .{al.value});
                    alias = try self.allocator.dupe(u8, al.value);
                }
            }
            return SqlSource{ .Table = SqlTable{ .database = database, .schema = schema, .name = name, .alias = alias } };
        }
    }
};

test "parse" {
    const allocator = std.testing.allocator;

    // Read from tokenizer
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    const sql: []const u8 = "SELECT *, u.*, o.name, 1.0 + o.vat::float as margin FROM users as u JOIN organisations as o USING (org_key) WHERE org_key = 0";
    var tokenizer = tokenize.Tokenizer.init(sql);
    while (tokenizer.next()) |token| {
        std.debug.print("Token: {} {s}\n", .{ token.token_type, token.value });
        try tokens.append(token);
    }

    // Parse token into AST
    var parser = SqlParser.init(allocator, try tokens.toOwnedSlice());
    _ = try parser.parseFrame();
}
