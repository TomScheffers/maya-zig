const std = @import("std");
const tokenize = @import("tokenize.zig");
const Token = tokenize.Token;

const SqlExpr: type = struct {};

const SqlSelection: type = union {
    Wildcard: void,
    NamedWildCard: []const u8,
    Expression: SqlExpr,
};

const SqlSource: type = union {
    Table: SqlTable,
    Frame: SqlFrame,
};

const SqlTable: type = struct { database: ?[]u8, schema: ?[]u8, name: []u8 };

const SqlJoinMethod: type = enum { LEFT, RIGHT, INNER };

const SqlJoinFrame: type = struct { right: SqlSource, method: SqlJoinMethod, using: std.ArrayList };

const SqlFrame: type = struct {
    selections: std.ArrayList(SqlSelection), // SELECT ...
    source: SqlSource, // FROM ...
    joins: ?std.ArrayList(SqlJoinFrame), // {} JOIN ...
    where: ?SqlExpr, // WHERE ...
    group_by: ?std.ArrayList(SqlExpr), // GROUP BY ...
    having: ?SqlExpr, // HAVING ...
};

const SqlParser = struct {
    tokens: []Token,
    position: usize,

    pub fn init(tokens: []Token) SqlParser {
        return SqlParser{ .tokens = tokens, .position = 0 };
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

    fn expect(self: *SqlParser, expected_type: tokenize.TokenType) !void {
        const token = self.next() orelse return error.UnexpectedEOF;
        if (token.token_type != expected_type) {
            return error.UnexpectedToken;
        }
    }

    fn parseFrame(self: *SqlParser) !SqlFrame {
        const selections = try self.parseSelections();
        const source = try self.parseSource();
        const joins = self.parseJoins() orelse null;
        const where_clause = self.parseWhere() orelse null;
        const group_by = self.parseGroupBy() orelse null;
        const having_clause = self.parseHaving() orelse null;

        return SqlFrame{
            .selections = selections,
            .source = source,
            .joins = joins,
            .where = where_clause,
            .group_by = group_by,
            .having = having_clause,
        };
    }

    fn parseSelections(self: *SqlParser) !std.ArrayList(SqlSelection) {
        try self.expect(tokenize.TokenType.Keyword); // Expect "SELECT"

        var selections = std.ArrayList(SqlSelection).init(std.heap.page_allocator);

        while (true) {
            const token = self.peek() orelse break;

            if (token.token_type == tokenize.TokenType.Symbol and token.value == ',') {
                _ = self.next(); // Skip comma
                continue;
            }

            if (token.token_type == tokenize.TokenType.Identifier or token.token_type == tokenize.TokenType.Wildcard) {
                const selection = if (token.token_type == TokenType.Wildcard) {
                    SqlSelection{ .Wildcard = {} };
                } else {
                    SqlSelection{ .NamedWildCard = token.value };
                };

                try selections.append(selection);
                _ = self.next(); // Move past identifier or wildcard
            } else {
                break;
            }
        }

        return selections;
    }
};

test "parse" {
    const allocator = std.testing.allocator;
    const sql: []const u8 = "SELECT *, u.*, o.name, 1.0 + o.vat::float as margin FROM users as u JOIN organisations as o USING (org_key) WHERE org_key = 0";
    _ = try parseSqlFrame(sql, allocator);
}
