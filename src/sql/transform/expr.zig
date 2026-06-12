//! libpg_query expression nodes → `sql/ast/expr.zig`.
//!
//! Pass `arena.allocator()` — the entire AST lives in one arena per query.

const std = @import("std");

const ast = @import("../ast/mod.zig");
const json = @import("json.zig");

pub const TransformExprError = error{
    OutOfMemory,
} || json.TransformJsonError;

pub fn transformExpr(
    allocator: std.mem.Allocator,
    node: std.json.Value,
) TransformExprError!*ast.Expr {
    const tagged = try json.taggedNode(node);

    const expr = try allocator.create(ast.Expr);

    if (std.mem.eql(u8, tagged.tag, "ColumnRef")) {
        expr.* = .{ .column = try transformColumnRef(allocator, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "A_Const")) {
        expr.* = .{ .literal = try transformConst(allocator, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "BoolExpr")) {
        expr.* = try transformBoolExpr(allocator, tagged.fields);
    } else if (std.mem.eql(u8, tagged.tag, "OpExpr")) {
        expr.* = try transformOpExpr(allocator, tagged.fields);
    } else if (std.mem.eql(u8, tagged.tag, "TypeCast")) {
        expr.* = try transformTypeCast(allocator, tagged.fields);
    } else if (std.mem.eql(u8, tagged.tag, "FuncCall")) {
        expr.* = try transformFuncCall(allocator, tagged.fields);
    } else if (std.mem.eql(u8, tagged.tag, "NullTest")) {
        expr.* = try transformNullTest(allocator, tagged.fields);
    } else {
        return error.UnsupportedNode;
    }

    return expr;
}

pub fn transformColumnRef(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.ColumnRef {
    const field_list = fields.get("fields") orelse return error.MissingField;
    const arr = try json.expectArray(field_list);

    if (arr.items.len == 1) {
        const string_node = try json.taggedNode(arr.items[0]);
        if (!std.mem.eql(u8, string_node.tag, "String")) return error.UnexpectedJson;
        const sval = json.optionalString(string_node.fields, "sval") orelse return error.MissingField;
        return .{ .bare = try allocator.dupe(u8, sval) };
    }

    const parts = try allocator.alloc([]const u8, arr.items.len);
    for (arr.items, 0..) |elem, i| {
        const string_node = try json.taggedNode(elem);
        if (!std.mem.eql(u8, string_node.tag, "String")) return error.UnexpectedJson;
        const sval = json.optionalString(string_node.fields, "sval") orelse return error.MissingField;
        parts[i] = try allocator.dupe(u8, sval);
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

fn transformBoolExpr(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Expr {
    const args = fields.get("args") orelse return error.MissingField;
    const arr = try json.expectArray(args);
    const boolop = json.optionalString(fields, "boolop") orelse return error.MissingField;

    if (std.mem.eql(u8, boolop, "NOT_EXPR")) {
        if (arr.items.len != 1) return error.UnexpectedJson;
        const inner = try transformExpr(allocator, arr.items[0]);
        return .{ .unary = .{ .op = .not, .expr = inner } };
    }

    if (arr.items.len != 2) return error.UnexpectedJson;
    const left = try transformExpr(allocator, arr.items[0]);
    const right = try transformExpr(allocator, arr.items[1]);

    const op: ast.BinaryOperator = if (std.mem.eql(u8, boolop, "AND_EXPR"))
        ._and
    else if (std.mem.eql(u8, boolop, "OR_EXPR"))
        ._or
    else
        return error.UnsupportedNode;

    return .{ .binary = .{ .left = left, .op = op, .right = right } };
}

fn transformOpExpr(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Expr {
    const args = fields.get("args") orelse return error.MissingField;
    const arr = try json.expectArray(args);
    const opno_value = fields.get("opno") orelse return error.MissingField;
    const opno: u32 = switch (opno_value) {
        .integer => |n| @intCast(n),
        else => return error.UnexpectedJson,
    };

    if (arr.items.len == 2) {
        const op = ast.BinaryOperator.fromOpno(opno) orelse return error.UnsupportedNode;
        const left = try transformExpr(allocator, arr.items[0]);
        const right = try transformExpr(allocator, arr.items[1]);
        return .{ .binary = .{ .left = left, .op = op, .right = right } };
    }
    if (arr.items.len == 1) {
        const op = ast.UnaryOperator.fromOpno(opno) orelse return error.UnsupportedNode;
        const inner = try transformExpr(allocator, arr.items[0]);
        return .{ .unary = .{ .op = op, .expr = inner } };
    }
    return error.UnexpectedJson;
}

// {
//   "TypeCast": {
//     "arg": {"A_Const": {"ival": {"ival": "42"}, "location": 1}},
//     "typeName": {"names": [{"String": {"sval": "int4"}}], "typemod": -1},
//     "location": 2
//   }
// }

fn transformName(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError![]const u8 {
    const name_field = fields.get("String") orelse return error.MissingField;
    const name_obj = try json.expectObject(name_field);
    const name = json.optionalString(name_obj, "sval") orelse return error.MissingField;
    return allocator.dupe(u8, name);
}

fn transformFirstNameInArray(allocator: std.mem.Allocator, names_arr: std.json.Array) TransformExprError![]const u8 {
    if (names_arr.items.len == 0) return error.MissingField;
    const first_name_entry = names_arr.items[0];
    const first_name_obj = try json.expectObject(first_name_entry);
    return transformName(allocator, first_name_obj);
}

fn transformNames(allocator: std.mem.Allocator, names_arr: std.json.Array) TransformExprError![]const []const u8 {
    const names = try allocator.alloc([]const u8, names_arr.items.len);
    for (names_arr.items, 0..) |item, i| {
        names[i] = try transformName(allocator, try json.expectObject(item));
    }
    return names;
}

fn transformTypeCast(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Expr {
    const arg_field = fields.get("arg") orelse return error.MissingField;
    const arg = try transformExpr(allocator, arg_field);

    const type_name_field = fields.get("typeName") orelse return error.MissingField;
    const type_name_obj = try json.expectObject(type_name_field);
    const names = type_name_obj.get("names") orelse return error.MissingField;
    const names_arr = try json.expectArray(names);
    const type_name = try transformFirstNameInArray(allocator, names_arr);

    return .{ .cast = .{ .expr = arg, .data_type = type_name } };
}

//  {"FuncCall":{"funcname":[{"String":{"sval":"count"}}],"args":[],"funcformat":0,"location":1}}

// \\{"FuncCall":{"funcname":[{"String":{"sval":"sum"}}],"args":[
// \\  {"ColumnRef":{"fields":[{"String":{"sval":"amount"}}],"location":1}}
// \\],"funcformat":0,"location":2}}

fn transformFunctionArg(allocator: std.mem.Allocator, fields: std.json.Value) TransformExprError!ast.FunctionArg {
    const tagged = try json.taggedNode(fields);

    if (std.mem.eql(u8, tagged.tag, "ColumnRef")) {
        const expr = try allocator.create(ast.Expr);
        expr.* = .{ .column = try transformColumnRef(allocator, tagged.fields) };
        return .{ .expr = expr };
    } else if (std.mem.eql(u8, tagged.tag, "A_Const")) {
        const expr = try allocator.create(ast.Expr);
        expr.* = .{ .literal = try transformConst(allocator, tagged.fields) };
        return .{ .expr = expr };
    } else {
        return error.UnsupportedNode;
    }
}

fn transformFuncCall(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Expr {
    const func_name_field = fields.get("funcname") orelse return error.MissingField;
    const func_names_arr = try json.expectArray(func_name_field);
    const func_names = try transformNames(allocator, func_names_arr);

    const args_field = fields.get("args") orelse return error.MissingField;
    const args_arr = try json.expectArray(args_field);

    const args = try allocator.alloc(ast.FunctionArg, args_arr.items.len);
    for (args_arr.items, 0..) |item, i| {
        args[i] = try transformFunctionArg(allocator, item);
    }

    return .{ .function = .{ .name = func_names, .args = args } };
}

fn transformNullTest(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformExprError!ast.Expr {
    const arg_field = fields.get("arg") orelse return error.MissingField;
    const arg = try transformExpr(allocator, arg_field);

    const nulltesttype = json.optionalString(fields, "nulltesttype") orelse return error.MissingField;
    if (std.mem.eql(u8, nulltesttype, "IS_NULL")) {
        return .{ .is_null = .{ .expr = arg, .negated = false } };
    } else if (std.mem.eql(u8, nulltesttype, "IS_NOT_NULL")) {
        return .{ .is_null = .{ .expr = arg, .negated = true } };
    }

    return error.UnsupportedNode;
}
