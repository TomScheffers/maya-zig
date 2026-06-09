//! libpg_query expression nodes → `sql/ast/expr.zig`.

const std = @import("std");

const ast = @import("../ast/mod.zig");
const json = @import("json.zig");

pub const TransformExprError = error{
    OutOfMemory,
} || json.TransformJsonError;

pub fn transformExpr(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    node: std.json.Value,
) TransformExprError!*ast.Expr {
    const tagged = try json.taggedNode(node);

    const expr = try arena.create(ast.Expr);

    if (std.mem.eql(u8, tagged.tag, "ColumnRef")) {
        expr.* = .{ .column = try transformColumnRef(arena, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "A_Const")) {
        expr.* = .{ .literal = try transformConst(allocator, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "BoolExpr")) {
        expr.* = try transformBoolExpr(allocator, arena, tagged.fields);
    } else if (std.mem.eql(u8, tagged.tag, "OpExpr")) {
        expr.* = try transformOpExpr(allocator, arena, tagged.fields);
    } else {
        return error.UnsupportedNode;
    }

    return expr;
}

pub fn transformColumnRef(arena: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.ColumnRef {
    const field_list = fields.get("fields") orelse return error.MissingField;
    const arr = try json.expectArray(field_list);

    if (arr.items.len == 1) {
        const string_node = try json.taggedNode(arr.items[0]);
        if (!std.mem.eql(u8, string_node.tag, "String")) return error.UnexpectedJson;
        const sval = json.optionalString(string_node.fields, "sval") orelse return error.MissingField;
        return .{ .bare = try arena.dupe(u8, sval) };
    }

    const parts = try arena.alloc([]const u8, arr.items.len);
    for (arr.items, 0..) |elem, i| {
        const string_node = try json.taggedNode(elem);
        if (!std.mem.eql(u8, string_node.tag, "String")) return error.UnexpectedJson;
        const sval = json.optionalString(string_node.fields, "sval") orelse return error.MissingField;
        parts[i] = try arena.dupe(u8, sval);
    }
    return .{ .qualified = parts };
}

pub fn transformConst(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Value {
    if (fields.get("isnull")) |v| {
        if (v == .bool and v.bool) return .{ .null = {} };
    }
    if (fields.get("ival")) |ival_wrapper| {
        const obj = try json.expectObject(ival_wrapper);
        const n = json.optionalString(obj, "ival") orelse return error.MissingField;
        return .{ .number = try allocator.dupe(u8, n) };
    }
    if (fields.get("fval")) |fval_wrapper| {
        const obj = try json.expectObject(fval_wrapper);
        const n = json.optionalString(obj, "fval") orelse return error.MissingField;
        return .{ .number = try allocator.dupe(u8, n) };
    }
    if (fields.get("sval")) |sval_wrapper| {
        const obj = try json.expectObject(sval_wrapper);
        const s = json.optionalString(obj, "sval") orelse return error.MissingField;
        return .{ .single_quoted = try allocator.dupe(u8, s) };
    }
    return error.UnexpectedJson;
}

fn transformBoolExpr(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    fields: std.json.ObjectMap,
) TransformExprError!ast.Expr {
    const args = fields.get("args") orelse return error.MissingField;
    const arr = try json.expectArray(args);
    const boolop = json.optionalString(fields, "boolop") orelse return error.MissingField;

    if (std.mem.eql(u8, boolop, "NOT_EXPR")) {
        if (arr.items.len != 1) return error.UnexpectedJson;
        const inner = try transformExpr(allocator, arena, arr.items[0]);
        return .{ .unary = .{ .op = .not, .expr = inner } };
    }

    if (arr.items.len != 2) return error.UnexpectedJson;
    const left = try transformExpr(allocator, arena, arr.items[0]);
    const right = try transformExpr(allocator, arena, arr.items[1]);

    std.debug.print("transformBoolExpr: {any}\n", .{left});
    std.debug.print("transformBoolExpr: {any}\n", .{right});
    std.debug.print("transformBoolExpr: {any}\n", .{boolop});

    const op: ast.BinaryOperator = if (std.mem.eql(u8, boolop, "AND_EXPR"))
        .@"and"
    else if (std.mem.eql(u8, boolop, "OR_EXPR"))
        .@"or"
    else
        return error.UnsupportedNode;

    return .{ .binary = .{ .left = left, .op = op, .right = right } };
}

fn transformOpExpr(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    fields: std.json.ObjectMap,
) TransformExprError!ast.Expr {
    const args = fields.get("args") orelse return error.MissingField;
    const arr = try json.expectArray(args);

    // TODO: map `opno` / `opname` to `BinaryOperator` / `UnaryOperator`
    if (arr.items.len == 2) {
        const left = try transformExpr(allocator, arena, arr.items[0]);
        const right = try transformExpr(allocator, arena, arr.items[1]);
        return .{ .binary = .{ .left = left, .op = .plus, .right = right } };
    }
    if (arr.items.len == 1) {
        const inner = try transformExpr(allocator, arena, arr.items[0]);
        return .{ .unary = .{ .op = .minus, .expr = inner } };
    }
    return error.UnexpectedJson;
}

test "transform ColumnRef bare and qualified" {
    const bare_fixture =
        \\{"ColumnRef":{"fields":[{"String":{"sval":"amount"}}],"location":1}}
    ;
    const qual_fixture =
        \\{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"amount"}}],"location":1}}
    ;

    var bare_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bare_fixture, .{});
    defer bare_parsed.deinit();
    var qual_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, qual_fixture, .{});
    defer qual_parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const bare = try transformExpr(arena.allocator(), arena.allocator(), bare_parsed.value);
    try std.testing.expectEqual(std.meta.activeTag(bare.*), .column);
    try std.testing.expectEqualStrings("amount", bare.column.bare);

    const qual = try transformExpr(arena.allocator(), arena.allocator(), qual_parsed.value);
    try std.testing.expectEqual(std.meta.activeTag(qual.*), .column);
    try std.testing.expectEqual(@as(usize, 2), qual.column.qualified.len);
    try std.testing.expectEqualStrings("o", qual.column.qualified[0]);
    try std.testing.expectEqualStrings("amount", qual.column.qualified[1]);
}

test "transform A_Const integer" {
    const fixture =
        \\{"A_Const":{"ival":{"ival":"42"},"location":1}}
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const node = try transformExpr(arena.allocator(), arena.allocator(), parsed.value);
    try std.testing.expectEqual(std.meta.activeTag(node.*), .literal);
    try std.testing.expectEqualStrings("42", node.literal.number);
}
