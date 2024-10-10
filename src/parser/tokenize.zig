const std = @import("std");

const TokenType = enum {
    Keyword,
    Identifier,
    Operator,
    StringLiteral,
    NumericLiteral,
    Whitespace,
    Symbol,
    Comment,
    EOF,
};

const Token = struct {
    token_type: TokenType,
    value: []const u8,
    position: usize,
};

const keywords = [_][]const u8{ "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "JOIN", "ORDER", "BY", "GROUP", "LIMIT" };

const Tokenizer = struct {
    input: []const u8,
    position: usize,

    pub fn init(input: []const u8) Tokenizer {
        return Tokenizer{ .input = input, .position = 0 };
    }

    pub fn next(self: *Tokenizer) ?Token {
        self.skip_whitespace();
        if (self.position >= self.input.len) return Token{ .token_type = .EOF, .value = "", .position = self.position };

        const c = self.input[self.position];

        if (Tokenizer.is_digit(c)) {
            return self.tokenize_number();
        } else if (Tokenizer.is_alpha(c)) {
            return self.tokenize_identifier_or_keyword();
        } else if (c == '"') {
            return self.tokenize_string();
        } else if (c == '-' and self.peek() == '-') {
            return self.tokenize_comment();
        } else {
            return self.tokenize_symbol_or_operator();
        }
    }

    fn skip_whitespace(self: *Tokenizer) void {
        while (self.position < self.input.len and (self.input[self.position] == ' ')) {
            self.position += 1;
        }
    }

    fn peek(self: *Tokenizer) ?u8 {
        if (self.position + 1 >= self.input.len) return null;
        return self.input[self.position + 1];
    }

    fn is_digit(c: u8) bool {
        return std.ascii.isDigit(c);
    }

    fn is_alpha(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn is_alphanumeric(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn tokenize_number(self: *Tokenizer) Token {
        const start_pos = self.position;
        while (self.position < self.input.len and (Tokenizer.is_digit(self.input[self.position]) or self.input[self.position] == '.')) {
            self.position += 1;
        }
        return Token{ .token_type = .NumericLiteral, .value = self.input[start_pos..self.position], .position = start_pos };
    }

    fn tokenize_identifier_or_keyword(self: *Tokenizer) Token {
        const start_pos = self.position;
        while ((self.position < self.input.len) and (Tokenizer.is_alphanumeric(self.input[self.position])) or self.input[self.position] == '.') {
            self.position += 1;
        }
        const value = self.input[start_pos..self.position];
        const token_type = if (Tokenizer.is_keyword(value)) TokenType.Keyword else TokenType.Identifier;
        return Token{ .token_type = token_type, .value = value, .position = start_pos };
    }

    fn is_keyword(value: []const u8) bool {
        for (keywords) |keyword| {
            if (std.mem.eql(u8, value, keyword)) {
                return true;
            }
        }
        return false;
    }

    fn tokenize_string(self: *Tokenizer) Token {
        const start_pos = self.position;
        self.position += 1; // skip opening quote
        while (self.position < self.input.len and self.input[self.position] != '"') {
            self.position += 1;
        }
        self.position += 1; // skip closing quote
        return Token{ .token_type = .StringLiteral, .value = self.input[start_pos..self.position], .position = start_pos };
    }

    fn tokenize_comment(self: *Tokenizer) Token {
        const start_pos = self.position;
        while (self.position < self.input.len and self.input[self.position] != '\n') {
            self.position += 1;
        }
        return Token{ .token_type = .Comment, .value = self.input[start_pos..self.position], .position = start_pos };
    }

    fn tokenize_symbol_or_operator(self: *Tokenizer) Token {
        const symbols = [_]u8{ '(', ')', ',', ';', '=', '>', '<' };
        const start_pos = self.position;

        for (symbols) |symbol| {
            if (symbol == self.input[self.position]) {
                self.position += 1;
                return Token{ .token_type = .Symbol, .value = self.input[start_pos..self.position], .position = start_pos };
            }
        }
        self.position += 1;
        return Token{ .token_type = .Operator, .value = self.input[start_pos..self.position], .position = start_pos };
    }
};

test "tokenize" {
    const sql: []const u8 = "SELECT *, u.*, o.name, 1.0 + o.vat::float as margin FROM users as u JOIN organisations as o USING (org_key) WHERE org_key = 0";
    var tokenizer = Tokenizer.init(sql);

    while (tokenizer.next()) |token| {
        if (token.token_type == TokenType.EOF) break;
        std.debug.print("Token: {} {s}\n", .{ token.token_type, token.value });
    }
}
