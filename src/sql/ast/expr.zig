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
    _and,
    _or,
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

    /// Map a libpg_query `OpExpr.opno` (PostgreSQL `pg_operator` OID) to a binary op.
    /// Returns `null` for unknown or unary-only operators.
    pub fn fromOpno(opno: u32) ?BinaryOperator {
        return switch (opno) {
            // = (selected pg_operator OIDs; expand as needed)
            91, 96, 98, 532, 533, 670, 774, 834, 1054, 1955, 2988, 3335 => .eq,
            // <>
            85, 518, 519, 531, 538, 539, 643, 671, 775, 835, 1956, 3336 => .ne,
            // <
            97, 412, 534, 535, 664, 672, 1058, 1957, 2314, 2326, 3884, 2862 => .lt,
            // <=
            522, 523, 540, 541, 2317, 2329, 3885, 2863 => .lte,
            // >
            520, 521, 536, 537, 2800 => .gt,
            // >=
            524, 525, 542, 543, 667, 1061, 1960, 3886, 2864 => .gte,
            // +
            550, 551, 552, 553, 586, 587, 903, 904 => .plus,
            // binary -
            554, 555, 556, 557, 588, 589, 905, 906 => .minus,
            // *
            514, 526, 544, 545, 590, 591, 592, 593, 794, 795, 796, 797 => .multiply,
            // /
            527, 528, 546, 547, 594, 595, 596, 597, 798, 799, 800, 801 => .divide,
            // %
            529, 530 => .modulo,
            // ||
            654, 657, 802, 1216, 2777, 2778 => .concat,
            // LIKE (~~)
            1207, 1209, 1211 => .like,
            // ILIKE (~~*)
            1625, 1627, 1629 => .ilike,
            // @@
            513 => .at_at,
            else => null,
        };
    }
};

pub const UnaryOperator = enum {
    @"not",
    minus,
    plus,
    bitwise_not,

    /// Map a libpg_query `OpExpr.opno` for prefix (`oprkind = 'l'`) operators.
    pub fn fromOpno(opno: u32) ?UnaryOperator {
        return switch (opno) {
            558, 559, 584, 585, 817, 818 => .minus,
            919, 920 => .plus,
            287, 288 => .bitwise_not,
            else => null,
        };
    }
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
    node.* = .{ .binary = .{ .left = left, .op = ._and, .right = right } };
    return node;
}

test "exprAnd builds AND binary node" {
    var left = Expr{ .column = .{ .bare = "a" } };
    var right = Expr{ .column = .{ .bare = "b" } };
    const node = try exprAnd(std.testing.allocator, &left, &right);
    defer std.testing.allocator.destroy(node);
    try std.testing.expectEqual(std.meta.activeTag(node.*), .binary);
    try std.testing.expect(node.binary.op == ._and);
}

test "BinaryOperator.fromOpno maps pg_operator OIDs" {
    try std.testing.expectEqual(BinaryOperator.eq, BinaryOperator.fromOpno(96));
    try std.testing.expectEqual(BinaryOperator.lt, BinaryOperator.fromOpno(97));
    try std.testing.expectEqual(BinaryOperator.plus, BinaryOperator.fromOpno(551));
    try std.testing.expectEqual(@as(?BinaryOperator, null), BinaryOperator.fromOpno(999_999));
}

test "UnaryOperator.fromOpno maps unary minus" {
    try std.testing.expectEqual(UnaryOperator.minus, UnaryOperator.fromOpno(558));
}
