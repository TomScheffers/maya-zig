const std = @import("std");

const ast_expr = @import("expr.zig");
const name = @import("name.zig");

pub const QualifiedName = name.QualifiedName;
pub const Alias = name.Alias;

/// Base table reference: `schema.table`, `table`, or `catalog.schema.table`.
pub const TableRef = struct {
    name: QualifiedName,
    alias: ?Alias = null,
    inherit: bool = true,
    location: i32 = -1,
};

/// SQL join kinds appearing in libpg_query `JoinExpr.jointype`.
pub const JoinKind = enum {
    inner,
    left,
    full,
    right,
    semi,
    anti,

    pub fn fromPgTag(tag: []const u8) ?JoinKind {
        if (std.mem.eql(u8, tag, "JOIN_INNER")) return .inner;
        if (std.mem.eql(u8, tag, "JOIN_LEFT")) return .left;
        if (std.mem.eql(u8, tag, "JOIN_FULL")) return .full;
        if (std.mem.eql(u8, tag, "JOIN_RIGHT")) return .right;
        if (std.mem.eql(u8, tag, "JOIN_SEMI")) return .semi;
        if (std.mem.eql(u8, tag, "JOIN_ANTI")) return .anti;
        return null;
    }
};

/// `JOIN … ON …` / `USING (…)` / `NATURAL JOIN`. Child items are nested arbitrarily.
pub const Join = struct {
    kind: JoinKind,
    natural: bool = false,
    left: *FromItem,
    right: *FromItem,
    /// `USING (a, b, …)` column names when present.
    using_columns: []const []const u8 = &.{},
    /// `ON` predicate. Filled in once `transform/expr.zig` exists.
    on: ?*ast_expr.Expr = null,
    alias: ?Alias = null,
};

/// Subquery in FROM: `(SELECT …) AS alias`. Transform not implemented yet.
pub const SubqueryRef = struct {
    _unimplemented: void = {},
};

pub const FromItem = union(enum) {
    table: TableRef,
    join: Join,
    subquery: SubqueryRef,
};

/// Raw parse-tree `SelectStmt.fromClause`: list of tables / join trees.
pub const FromClause = struct {
    items: []*FromItem,
};
