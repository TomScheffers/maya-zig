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
    Cast: []const u8,

    pub fn deinit(self: SqlExpr) void {
        _ = self;
    }
};

const SqlNamedExpr = struct {
    expr: SqlExpr,
    name: ?[]const u8,

    pub fn fromSqlExpr(expr: SqlExpr) SqlNamedExpr {
        return SqlNamedExpr{ .expr = expr, .name = null };
    }

    pub fn deinit(self: SqlNamedExpr) void {
        self.expr.deinit();
    }
};

const SqlSource: type = union(enum) {
    Table: SqlTable,
    Frame: *const SqlFrame,

    pub fn deinit(self: SqlSource) void {
        switch (self) {
            inline else => |x| x.deinit(),
        }
    }
};

const SqlTable: type = struct {
    database: ?[]u8,
    schema: ?[]u8,
    name: []u8,
    alias: ?[]u8,

    pub fn deinit(self: SqlTable) void {
        _ = self;
    }
};

const SqlJoinMethod: type = enum {
    LEFT,
    RIGHT,
    INNER,
    OUTER,
    ANTI,

    pub fn fromKeyword(keyword: []const u8) ?SqlJoinMethod {
        if ((std.mem.eql(u8, keyword, "INNER")) or (std.mem.eql(u8, keyword, "JOIN"))) {
            return SqlJoinMethod.INNER;
        } else if (std.mem.eql(u8, keyword, "LEFT")) {
            return SqlJoinMethod.LEFT;
        } else if (std.mem.eql(u8, keyword, "RIGHT")) {
            return SqlJoinMethod.RIGHT;
        } else if (std.mem.eql(u8, keyword, "OUTER")) {
            return SqlJoinMethod.OUTER;
        } else if (std.mem.eql(u8, keyword, "ANTI")) {
            return SqlJoinMethod.ANTI;
        } else {
            return null;
        }
    }
};

const SqlJoinFrame: type = struct {
    right: SqlSource,
    method: SqlJoinMethod,
    on: ?SqlNamedExpr,
    using: ?std.array_list.Managed([]const u8),

    pub fn deinit(self: SqlJoinFrame) void {
        self.right.deinit();
        if (self.on) |o| {
            o.deinit();
        }
        if (self.using) |u| {
            u.deinit();
        }
    }
};

const SqlFrame: type = struct {
    selections: std.array_list.Managed(SqlNamedExpr), // SELECT ...
    source: SqlSource, // FROM ...
    joins: std.array_list.Managed(SqlJoinFrame), // {} JOIN ...
    where: ?SqlExpr, // WHERE ...
    // group_by: ?std.array_list.Managed(SqlExpr), // GROUP BY ...
    // having: ?SqlExpr, // HAVING ...

    pub fn deinit(self: SqlFrame) void {
        for (self.selections.items) |s| {
            s.deinit();
        }
        self.selections.deinit();
        self.source.deinit();
        for (self.joins.items) |j| {
            j.deinit();
        }
        self.joins.deinit();
        if (self.where) |w| {
            w.deinit();
        }
    }
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
            .joins = try self.parseJoins(),
            .where = try self.parseWhere(),
            // .group_by = group_by,
            // .having = having_clause,
        };
        // TODO: Skip ) and read alias if subquery
        return frame;
    }

    fn parseSelection(self: *SqlParser) ParserErrors!?SqlNamedExpr {
        var selection: ?SqlNamedExpr = null;
        while (true) {
            const token = self.peek() orelse break;

            // Check if we need to terminate for FROM
            if ((token.token_type == TokenType.Keyword) and std.mem.eql(u8, token.value, "FROM")) return selection;

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
                    } else {
                        std.debug.print("\nPlease implement {s}", .{token.value});
                    }
                },
                .Symbol => {
                    if (token.value[0] == ',') {
                        self.position += 1;
                        break;
                    } else if ((selection == null) and (token.value[0] == '*')) {
                        selection = SqlNamedExpr.fromSqlExpr(SqlExpr{ .Wildcard = undefined });
                    } else {
                        std.debug.print("\nPlease implement {s}", .{token.value});
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
        return selection;
    }

    fn parseSelections(self: *SqlParser) ParserErrors!std.array_list.Managed(SqlNamedExpr) {
        try self.expect(tokenize.TokenType.Keyword); // Expect "SELECT"

        var selections = std.array_list.Managed(SqlNamedExpr).init(self.allocator);
        while (true) {
            const selection = try self.parseSelection();
            if (selection) |s| {
                try selections.append(s);
            } else {
                break;
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

    fn parseJoin(self: *SqlParser) ParserErrors!?SqlJoinFrame {
        const token = self.peek();
        if (token) |tk| {
            if (tk.token_type == TokenType.Keyword) {
                const join_method = SqlJoinMethod.fromKeyword(tk.value);
                if (join_method) |jm| {
                    const right = try self.parseSource();

                    const jtoken = self.peek();
                    if (jtoken) |jtk| {
                        self.position += 1;
                        if (std.mem.eql(u8, jtk.value, "USING")) { // (a, b, c)
                            var using = std.array_list.Managed([]const u8).init(self.allocator);
                            if (self.next().?.value[0] == '(') {
                                while (self.next()) |utk| {
                                    if (utk.value[0] == ')') {
                                        break;
                                    } else {
                                        try using.append(utk.value);
                                    }
                                }
                                return SqlJoinFrame{ .method = jm, .right = right, .on = null, .using = using };
                            } else {
                                return error.UnexpectedToken;
                            }
                        } else if (std.mem.eql(u8, jtk.value, "ON")) {
                            const on = try self.parseSelection();
                            return SqlJoinFrame{ .method = jm, .right = right, .on = on, .using = null };
                        }
                    }
                    return SqlJoinFrame{ .method = jm, .right = right, .on = null, .using = null };
                }
            }
        }
        return null;
    }

    fn parseJoins(self: *SqlParser) ParserErrors!std.array_list.Managed(SqlJoinFrame) {
        var joins = std.array_list.Managed(SqlJoinFrame).init(self.allocator);
        while (try self.parseJoin()) |join| {
            try joins.append(join);
        }
        return joins;
    }

    fn parseWhere(self: *SqlParser) ParserErrors!?SqlExpr {
        const token = self.peek();
        std.debug.print("Where {s}", .{token.?.value});

        if (token) |tk| {
            if ((tk.token_type == TokenType.Keyword) and (std.mem.eql(u8, tk.value, "WHERE"))) {
                self.position += 1;
                const expr = try self.parseSelection();
                if (expr) |e| {
                    return e.expr;
                }
            }
        }
        return null;
    }
};

test "parse" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // const allocator = std.testing.allocator;

    // Read from tokenizer
    var tokens = std.array_list.Managed(Token).init(allocator);
    defer tokens.deinit();

    const sql: []const u8 = "SELECT *, u.*, o.name, 1.0 + o.vat::float as margin FROM users as u JOIN organisations as o USING (org_key) WHERE org_key = 0";
    var tokenizer = tokenize.Tokenizer.init(sql);
    while (tokenizer.next()) |token| {
        std.debug.print("Token: {} {s}\n", .{ token.token_type, token.value });
        try tokens.append(token);
    }

    // Parse token into AST
    var parser = SqlParser.init(allocator, try tokens.toOwnedSlice());
    const frame = try parser.parseFrame();
    defer frame.deinit();
}
