//! SQL expression AST.
//!
//! Shape follows sqlparser `Expr` and maps from libpg_query nodes
//! (`ColumnRef`, `A_Const`, `OpExpr`, `FuncCall`, …).
//! This is the syntax tree layer; `core/expr.zig` is runtime eval IR.

const std = @import("std");

const Value = @import("value.zig").Value;

/// `a`, `schema.table.col`, etc. (pre-bind).
pub const ColumnRef = union(enum) {
    /// Single identifier: `amount`.
    bare: []const u8,
    /// Qualified path; last element is the column name.
    qualified: []const []const u8,
};

pub const BinaryOperator = enum {
    @"and",
    @"or",
    eq,
    ne,
    lt,
    lte,
    gt,
    gte,
    like,
    ilike,
    similar,
    plus,
    minus,
    multiply,
    divide,
    modulo,
    concat,
    at_at,
};

pub const UnaryOperator = enum {
    @"not",
    minus,
    plus,
    bitwise_not,
};

pub const FunctionArg = union(enum) {
    expr: *Expr,
    named: struct {
        name: []const u8,
        value: *Expr,
    },
    table: *Expr,
    _placeholder: void,
};

pub const FunctionCall = struct {
    name: []const []const u8,
    args: []FunctionArg,
    distinct: bool = false,
    filter: ?*Expr = null,
    over: ?*anyopaque = null,
};

pub const CastExpr = struct {
    expr: *Expr,
    data_type: []const u8,
};

pub const BetweenExpr = struct {
    expr: *Expr,
    negated: bool,
    low: *Expr,
    high: *Expr,
};

pub const CaseBranch = struct {
    condition: *Expr,
    result: *Expr,
};

pub const CaseExpr = struct {
    operand: ?*Expr,
    branches: []CaseBranch,
    else_result: ?*Expr,
};

pub const InListExpr = struct {
    expr: *Expr,
    list: []*Expr,
    negated: bool,
};

pub const SubqueryExpr = struct {
    _unimplemented: void = {},
};

pub const Expr = union(enum) {
    column: ColumnRef,
    literal: Value,
    binary: struct {
        left: *Expr,
        op: BinaryOperator,
        right: *Expr,
    },
    unary: struct {
        op: UnaryOperator,
        expr: *Expr,
    },
    function: FunctionCall,
    cast: CastExpr,
    between: BetweenExpr,
    case: CaseExpr,
    is_null: struct {
        expr: *Expr,
        negated: bool,
    },
    is_true: struct {
        expr: *Expr,
        negated: bool,
    },
    is_false: struct {
        expr: *Expr,
        negated: bool,
    },
    in_list: InListExpr,
    nested: *Expr,
    subquery: SubqueryExpr,
    wildcard: struct {
        qualifier: ?[]const u8 = null,
    },
};

pub fn exprAnd(allocator: std.mem.Allocator, left: *Expr, right: *Expr) !*Expr {
    const node = try allocator.create(Expr);
    node.* = .{ .binary = .{ .left = left, .op = .@"and", .right = right } };
    return node;
}

test "exprAnd builds AND binary node" {
    var left = Expr{ .column = .{ .bare = "a" } };
    var right = Expr{ .column = .{ .bare = "b" } };
    const node = try exprAnd(std.testing.allocator, &left, &right);
    defer std.testing.allocator.destroy(node);
    try std.testing.expectEqual(std.meta.activeTag(node.*), .binary);
    try std.testing.expect(node.binary.op == .@"and");
}
