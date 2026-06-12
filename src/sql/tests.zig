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
        return exprm.transformExpr(self.arena.allocator(), self.parsed.value);
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
    try std.testing.expect(expr.binary.op == ._and);
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
    try std.testing.expect(expr.binary.op == ._or);
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
        \\{"OpExpr":{"opno":558,"args":[
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
        \\{"TypeCast":{"arg":{"A_Const":{"ival":{"ival":"42"},"location":1}},"typeName":{"names":[{"String":{"sval":"int4"}}],"typemod":-1},"location":2}}
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

    const item = try from.transformFromItem(ctx.arena.allocator(), ctx.parsed.value);

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

    const item = try from.transformFromItem(ctx.arena.allocator(), ctx.parsed.value);

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

    const from_clause = try from.transformFromClause(ctx.arena.allocator(), ctx.parsed.value);

    try std.testing.expectEqual(@as(usize, 2), from_clause.items.len);
    try std.testing.expectEqual(ast.FromItem.join, std.meta.activeTag(from_clause.items[0].*));
    try std.testing.expectEqual(ast.FromItem.table, std.meta.activeTag(from_clause.items[1].*));
    try std.testing.expectEqualStrings("c", from_clause.items[1].*.table.name.relation);
}

test "full query v1" {
    const json_txt =
        \\ {"version":180004,"stmts":[{"stmt":{"SelectStmt":{"targetList":[{"ResTarget":{"val":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":7}},"location":7}},{"ResTarget":{"name":"total","val":{"TypeCast":{"arg":{"FuncCall":{"funcname":[{"String":{"sval":"sum"}}],"args":[{"ColumnRef":{"fields":[{"String":{"sval":"i"}},{"String":{"sval":"qty"}}],"location":24}}],"funcformat":"COERCE_EXPLICIT_CALL","location":20}},"typeName":{"names":[{"String":{"sval":"int4"}}],"typemod":-1,"location":32},"location":30}},"location":20}},{"ResTarget":{"val":{"FuncCall":{"funcname":[{"String":{"sval":"count"}}],"agg_star":true,"funcformat":"COERCE_EXPLICIT_CALL","location":54}},"location":54}},{"ResTarget":{"name":"customer_name","val":{"FuncCall":{"funcname":[{"String":{"sval":"upper"}}],"args":[{"ColumnRef":{"fields":[{"String":{"sval":"c"}},{"String":{"sval":"name"}}],"location":77}}],"funcformat":"COERCE_EXPLICIT_CALL","location":71}},"location":71}}],"fromClause":[{"JoinExpr":{"jointype":"JOIN_LEFT","larg":{"JoinExpr":{"jointype":"JOIN_INNER","larg":{"RangeVar":{"schemaname":"public","relname":"orders","inh":true,"relpersistence":"p","alias":{"aliasname":"o"},"location":107}},"rarg":{"RangeVar":{"schemaname":"public","relname":"items","inh":true,"relpersistence":"p","alias":{"aliasname":"i"},"location":134}},"quals":{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"="}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":152}},"rexpr":{"ColumnRef":{"fields":[{"String":{"sval":"i"}},{"String":{"sval":"order_id"}}],"location":159}},"location":157}}}},"rarg":{"RangeVar":{"schemaname":"public","relname":"customers","inh":true,"relpersistence":"p","alias":{"aliasname":"c"},"location":180}},"quals":{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"="}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"c"}},{"String":{"sval":"id"}}],"location":202}},"rexpr":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"customer_id"}}],"location":209}},"location":207}}}}],"whereClause":{"BoolExpr":{"boolop":"AND_EXPR","args":[{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"="}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"status"}}],"location":229}},"rexpr":{"A_Const":{"sval":{"sval":"open"},"location":240}},"location":238}},{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"\u003e"}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"i"}},{"String":{"sval":"qty"}}],"location":253}},"rexpr":{"A_Const":{"ival":{"ival":100},"location":261}},"location":259}},{"SubLink":{"subLinkType":"ANY_SUBLINK","testexpr":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":271}},"subselect":{"SelectStmt":{"targetList":[{"ResTarget":{"val":{"ColumnRef":{"fields":[{"String":{"sval":"order_id"}}],"location":287}},"location":287}}],"fromClause":[{"RangeVar":{"schemaname":"public","relname":"archived","inh":true,"relpersistence":"p","location":301}}],"whereClause":{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"="}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"year"}}],"location":323}},"rexpr":{"A_Const":{"ival":{"ival":2024},"location":330}},"location":328}},"limitOption":"LIMIT_OPTION_DEFAULT","op":"SETOP_NONE"}},"location":276}},{"NullTest":{"arg":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"email"}}],"location":342}},"nulltesttype":"IS_NOT_NULL","location":350}},{"BoolExpr":{"boolop":"NOT_EXPR","args":[{"ColumnRef":{"fields":[{"String":{"sval":"c"}},{"String":{"sval":"active"}}],"location":372}}],"location":368}},{"BoolExpr":{"boolop":"OR_EXPR","args":[{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"\u003c"}}],"lexpr":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"amount"}}],"location":388}},"rexpr":{"A_Const":{"ival":{"ival":1000},"location":399}},"location":397}},{"NullTest":{"arg":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"discount"}}],"location":407}},"nulltesttype":"IS_NULL","location":418}}],"location":404}}],"location":249}},"groupClause":[{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":436}},{"ColumnRef":{"fields":[{"String":{"sval":"c"}},{"String":{"sval":"name"}}],"location":442}}],"havingClause":{"A_Expr":{"kind":"AEXPR_OP","name":[{"String":{"sval":"\u003e"}}],"lexpr":{"FuncCall":{"funcname":[{"String":{"sval":"sum"}}],"args":[{"ColumnRef":{"fields":[{"String":{"sval":"i"}},{"String":{"sval":"qty"}}],"location":460}}],"funcformat":"COERCE_EXPLICIT_CALL","location":456}},"rexpr":{"A_Const":{"ival":{"ival":500},"location":469}},"location":467}},"sortClause":[{"SortBy":{"node":{"ColumnRef":{"fields":[{"String":{"sval":"total"}}],"location":482}},"sortby_dir":"SORTBY_DESC","sortby_nulls":"SORTBY_NULLS_DEFAULT","location":-1}},{"SortBy":{"node":{"ColumnRef":{"fields":[{"String":{"sval":"o"}},{"String":{"sval":"id"}}],"location":494}},"sortby_dir":"SORTBY_DEFAULT","sortby_nulls":"SORTBY_NULLS_DEFAULT","location":-1}}],"limitOffset":{"A_Const":{"ival":{"ival":5},"location":515}},"limitCount":{"A_Const":{"ival":{"ival":10},"location":505}},"limitOption":"LIMIT_OPTION_COUNT","op":"SETOP_NONE"}}}]}
    ;

    var ctx = try TestCtx.init(json_txt);
    defer ctx.deinit();

    // TODO: Implement

}
