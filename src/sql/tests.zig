//! TDD tests for `transform/expr.zig`. Run with `zig build test`.

const std = @import("std");

const json = @import("transform/json.zig");
const ast = @import("ast/mod.zig");
const exprm = @import("transform/expr.zig");
const from = @import("transform/from.zig");

const TestCtx = struct {
    parsed: std.json.Parsed(std.json.Value),
    arena: std.heap.ArenaAllocator,

    fn init(json_text: []const u8) !TestCtx {
        return .{
            .parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_text, .{}),
            .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        };
    }

    fn deinit(self: *TestCtx) void {
        self.parsed.deinit();
        self.arena.deinit();
    }

    fn transform_expr(self: *TestCtx) !*ast.Expr {
        return exprm.transformExpr(self.arena.allocator(), self.arena.allocator(), self.parsed.value);
    }
};

test "A_Const null" {
    const json_txt =
        \\{"A_Const":{"isnull":true,"location":1}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .literal);
    try std.testing.expectEqual(std.meta.activeTag(expr.literal), .null);
}

test "A_Const float literal" {
    const json_txt =
        \\{"A_Const":{"fval":{"fval":"3.14"},"location":1}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .literal);
    try std.testing.expectEqual(std.meta.activeTag(expr.literal), .number);
    try std.testing.expectEqualStrings("3.14", expr.literal.number);
}

test "A_Const string literal" {
    const json_txt =
        \\{"A_Const":{"sval":{"sval":"hello"},"location":1}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .literal);
    try std.testing.expectEqual(std.meta.activeTag(expr.literal), .single_quoted);
    try std.testing.expectEqualStrings("hello", expr.literal.single_quoted);
}

test "BoolExpr AND" {
    const json_txt =
        \\{"BoolExpr":{"boolop":"AND_EXPR","args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"a"}}],"location":1}},
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"b"}}],"location":2}}
        \\],"location":3}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .binary);
    try std.testing.expect(expr.binary.op == .@"and");
    try std.testing.expectEqual(std.meta.activeTag(expr.binary.left.*), .column);
    try std.testing.expectEqualStrings("a", expr.binary.left.column.bare);
    try std.testing.expectEqual(std.meta.activeTag(expr.binary.right.*), .column);
    try std.testing.expectEqualStrings("b", expr.binary.right.column.bare);
}

test "BoolExpr OR" {
    const json_txt =
        \\{"BoolExpr":{"boolop":"OR_EXPR","args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"x"}}],"location":1}},
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"y"}}],"location":2}}
        \\],"location":3}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .binary);
    try std.testing.expect(expr.binary.op == .@"or");
}

test "BoolExpr NOT" {
    const json_txt =
        \\{"BoolExpr":{"boolop":"NOT_EXPR","args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"active"}}],"location":1}}
        \\],"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .unary);
    try std.testing.expect(expr.unary.op == .not);
    try std.testing.expectEqual(std.meta.activeTag(expr.unary.expr.*), .column);
    try std.testing.expectEqualStrings("active", expr.unary.expr.column.bare);
}

test "OpExpr equality" {
    const json_txt =
        \\{"OpExpr":{"opno":96,"args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"id"}}],"location":1}},
        \\  {"A_Const":{"ival":{"ival":"1"},"location":2}}
        \\],"location":3}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .binary);
    try std.testing.expect(expr.binary.op == .eq);
    try std.testing.expectEqualStrings("id", expr.binary.left.column.bare);
    try std.testing.expectEqualStrings("1", expr.binary.right.literal.number);
}

test "OpExpr less than" {
    const json_txt =
        \\{"OpExpr":{"opno":97,"args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"amount"}}],"location":1}},
        \\  {"A_Const":{"ival":{"ival":"100"},"location":2}}
        \\],"location":3}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .binary);
    try std.testing.expect(expr.binary.op == .lt);
}

test "OpExpr unary minus" {
    const json_txt =
        \\{"OpExpr":{"opno":254,"args":[
        \\  {"A_Const":{"ival":{"ival":"5"},"location":1}}
        \\],"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .unary);
    try std.testing.expect(expr.unary.op == .minus);
    try std.testing.expectEqualStrings("5", expr.unary.expr.literal.number);
}

test "NullTest IS NULL" {
    const json_txt =
        \\{"NullTest":{"arg":{"ColumnRef":{"fields":[{"String":{"sval":"email"}}],"location":1}},"nulltesttype":"IS_NULL","argisrow":false,"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .is_null);
    try std.testing.expect(!expr.is_null.negated);
    try std.testing.expectEqualStrings("email", expr.is_null.expr.column.bare);
}

test "NullTest IS NOT NULL" {
    const json_txt =
        \\{"NullTest":{"arg":{"ColumnRef":{"fields":[{"String":{"sval":"email"}}],"location":1}},"nulltesttype":"IS_NOT_NULL","argisrow":false,"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .is_null);
    try std.testing.expect(expr.is_null.negated);
}

test "FuncCall count star" {
    const json_txt =
        \\{"FuncCall":{"funcname":[{"String":{"sval":"count"}}],"args":[],"funcformat":0,"location":1}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .function);
    try std.testing.expectEqual(@as(usize, 1), expr.function.name.len);
    try std.testing.expectEqualStrings("count", expr.function.name[0]);
    try std.testing.expectEqual(@as(usize, 0), expr.function.args.len);
}

test "FuncCall with column arg" {
    const json_txt =
        \\{"FuncCall":{"funcname":[{"String":{"sval":"sum"}}],"args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"amount"}}],"location":1}}
        \\],"funcformat":0,"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .function);
    try std.testing.expectEqualStrings("sum", expr.function.name[0]);
    try std.testing.expectEqual(@as(usize, 1), expr.function.args.len);
    try std.testing.expectEqual(std.meta.activeTag(expr.function.args[0]), .expr);
    try std.testing.expectEqualStrings("amount", expr.function.args[0].expr.column.bare);
}

test "TypeCast to integer" {
    const json_txt =
        \\{"TypeCast":{"arg":{"A_Const":{"ival":{"ival":"42"},"location":1}},"typeName":{"TypeName":{"names":[{"String":{"sval":"int4"}}],"typemod":-1}},"location":2}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();
    const expr = try ctx.transform_expr();

    try std.testing.expectEqual(std.meta.activeTag(expr.*), .cast);
    try std.testing.expectEqualStrings("42", expr.cast.expr.literal.number);
    try std.testing.expectEqualStrings("int4", expr.cast.data_type);
}

test "RangeVar with schema" {
    const json_txt =
        \\{"RangeVar":{"schemaname":"public","relname":"orders","inh":true,"relpersistence":"p","location":1}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();

    const table = try from.transformRangeVar(ctx.arena.allocator(), (try json.taggedNode(ctx.parsed.value)).fields);

    try std.testing.expectEqualStrings("public", table.name.schema.?);
    try std.testing.expectEqualStrings("orders", table.name.relation);
}

test "JoinExpr USING columns" {
    const json_txt =
        \\{"JoinExpr":{"jointype":"JOIN_INNER","isNatural":false,"larg":{"RangeVar":{"relname":"a","inh":true,"relpersistence":"p","location":1}},"rarg":{"RangeVar":{"relname":"b","inh":true,"relpersistence":"p","location":2}},"usingClause":[{"String":{"sval":"id"}},{"String":{"sval":"ts"}}],"rtindex":0}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();

    const item = try from.transformFromItem(ctx.arena.allocator(), ctx.arena.allocator(), ctx.parsed.value);

    try std.testing.expectEqual(@as(usize, 2), item.join.using_columns.len);
    try std.testing.expectEqualStrings("id", item.join.using_columns[0]);
    try std.testing.expectEqualStrings("ts", item.join.using_columns[1]);
    try std.testing.expect(item.join.on == null);
}

test "JoinExpr LEFT with ON quals" {
    const json_txt =
        \\{"JoinExpr":{"jointype":"JOIN_LEFT","isNatural":false,"larg":{"RangeVar":{"relname":"orders","inh":true,"relpersistence":"p","location":1}},"rarg":{"RangeVar":{"relname":"items","inh":true,"relpersistence":"p","location":2}},"quals":{"OpExpr":{"opno":96,"args":[
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":3}},
        \\  {"ColumnRef":{"fields":[{"String":{"sval":"i"}},{"String":{"sval":"order_id"}}],"location":4}}
        \\],"location":5}},"rtindex":0}}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();

    const item = try from.transformFromItem(ctx.arena.allocator(), ctx.arena.allocator(), ctx.parsed.value);

    try std.testing.expect(item.join.kind == .left);
    try std.testing.expect(item.join.on != null);
    try std.testing.expectEqual(std.meta.activeTag(item.join.on.?.*), .binary);
    try std.testing.expect(item.join.on.?.binary.op == .eq);
    try std.testing.expectEqual(@as(usize, 2), item.join.on.?.binary.left.column.qualified.len);
    try std.testing.expectEqualStrings("o", item.join.on.?.binary.left.column.qualified[0]);
    try std.testing.expectEqualStrings("id", item.join.on.?.binary.left.column.qualified[1]);
}

test "FROM clause join tree" {
    const json_txt =
        \\[
        \\  {"JoinExpr":{"jointype":"JOIN_INNER","isNatural":false,"larg":{"RangeVar":{"relname":"a","inh":true,"relpersistence":"p","location":1}},"rarg":{"RangeVar":{"relname":"b","inh":true,"relpersistence":"p","location":2}},"rtindex":0}},
        \\  {"RangeVar":{"relname":"c","inh":true,"relpersistence":"p","location":3}}
        \\]
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();

    const from_clause = try from.transformFromClause(ctx.arena.allocator(), ctx.arena.allocator(), ctx.parsed.value);

    try std.testing.expectEqual(@as(usize, 2), from_clause.items.len);
    try std.testing.expectEqual(ast.FromItem.join, std.meta.activeTag(from_clause.items[0].*));
    try std.testing.expectEqual(ast.FromItem.table, std.meta.activeTag(from_clause.items[1].*));
    try std.testing.expectEqualStrings("c", from_clause.items[1].*.table.name.relation);
}
