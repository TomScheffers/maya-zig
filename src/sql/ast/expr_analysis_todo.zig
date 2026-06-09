//! TDD tests for `ast/expr_analysis.zig`. Run with `zig build test`.

const std = @import("std");

const analysis = @import("expr_analysis.zig");
const ast = @import("expr.zig");

test "todo.analysis: exprToColumn bare identifier" {
    const expr = ast.Expr{ .column = .{ .bare = "amount" } };

    const col = try analysis.exprToColumn(&expr);

    try std.testing.expectEqualStrings("amount", col.name);
    try std.testing.expectEqualStrings("", col.alias);
    try std.testing.expect(col.table == null);
}

test "todo.analysis: exprToColumn qualified alias.column" {
    const parts = [_][]const u8{ "o", "amount" };
    const expr = ast.Expr{ .column = .{ .qualified = &parts } };

    const col = try analysis.exprToColumn(&expr);

    try std.testing.expectEqualStrings("o", col.alias);
    try std.testing.expectEqualStrings("amount", col.name);
}

test "todo.analysis: exprToColumn rejects non-column expr" {
    const expr = ast.Expr{ .literal = .{ .number = "1" } };

    try std.testing.expectError(analysis.AnalysisError.NotAColumn, analysis.exprToColumn(&expr));
}

test "todo.analysis: referencedColumns single bare column" {
    const expr = ast.Expr{ .column = .{ .bare = "x" } };

    const cols = try analysis.referencedColumns(&expr, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cols.len);
    try std.testing.expectEqualStrings("x", cols[0].name);
}

test "todo.analysis: referencedColumns binary AND" {
    var left = ast.Expr{ .column = .{ .bare = "a" } };
    var right = ast.Expr{ .column = .{ .bare = "b" } };
    const root = ast.Expr{
        .binary = .{ .left = &left, .op = .@"and", .right = &right },
    };

    const cols = try analysis.referencedColumns(&root, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), cols.len);
    try std.testing.expectEqualStrings("a", cols[0].name);
    try std.testing.expectEqualStrings("b", cols[1].name);
}

test "todo.analysis: referencedColumns unary NOT" {
    var inner = ast.Expr{ .column = .{ .bare = "flag" } };
    const root = ast.Expr{ .unary = .{ .op = .@"not", .expr = &inner } };

    const cols = try analysis.referencedColumns(&root, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cols.len);
    try std.testing.expectEqualStrings("flag", cols[0].name);
}

test "todo.analysis: referencedColumns nested binary" {
    var a = ast.Expr{ .column = .{ .bare = "x" } };
    var b = ast.Expr{ .column = .{ .bare = "y" } };
    var and_node = ast.Expr{ .binary = .{ .left = &a, .op = .@"and", .right = &b } };
    var c = ast.Expr{ .column = .{ .bare = "z" } };
    const root = ast.Expr{ .binary = .{ .left = &and_node, .op = .@"or", .right = &c } };

    const cols = try analysis.referencedColumns(&root, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), cols.len);
    try std.testing.expectEqualStrings("x", cols[0].name);
    try std.testing.expectEqualStrings("y", cols[1].name);
    try std.testing.expectEqualStrings("z", cols[2].name);
}
