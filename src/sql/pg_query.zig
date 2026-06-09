//! Thin Zig wrapper around libpg_query (PostgreSQL 18 parser).
const std = @import("std");
const c = @import("pg_query_c");

pub const postgres_version = c.PG_VERSION;
pub const postgres_version_num: c_int = c.PG_VERSION_NUM;

pub const ParseFailure = struct {
    message: []const u8,
    cursorpos: c_int,

    pub fn format(self: ParseFailure, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.cursorpos >= 0) {
            try writer.print("SQL parse error at position {d}: {s}", .{ self.cursorpos, self.message });
        } else {
            try writer.print("SQL parse error: {s}", .{self.message});
        }
    }
};

pub const ParseResult = union(enum) {
    ok: []u8,
    err: ParseFailure,
};

/// Parse SQL and return the JSON parse tree. Caller owns `.ok` slice on success.
pub fn parse(allocator: std.mem.Allocator, sql: []const u8) !ParseResult {
    const sql_z = try allocator.dupeZ(u8, sql);
    defer allocator.free(sql_z);

    const result = c.pg_query_parse(sql_z.ptr);
    defer c.pg_query_free_parse_result(result);

    if (result.@"error") |err| {
        const message = if (err.*.message != null) std.mem.span(err.*.message) else "unknown parse error";
        return .{ .err = .{
            .message = message,
            .cursorpos = err.*.cursorpos,
        } };
    }

    const tree = result.parse_tree orelse return .{ .err = .{
        .message = "parser returned no parse tree",
        .cursorpos = -1,
    } };

    return .{ .ok = try allocator.dupe(u8, std.mem.span(tree)) };
}

test "parse simple select" {
    const parsed = try parse(std.testing.allocator, "SELECT 1");
    const json = switch (parsed) {
        .ok => |tree| tree,
        .err => |failure| std.debug.panic("unexpected parse failure: {}", .{failure}),
    };
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "SelectStmt") != null);
    try std.testing.expect(std.mem.eql(u8, postgres_version, "18.4"));
}
