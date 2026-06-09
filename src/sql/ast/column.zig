//! Column references for expressions and analysis.
//!
//! Mirrors `mayadb` `Column { table, alias, name }` after binding.
//! In the raw AST, use `ColumnRef` in `expr.zig` before names are resolved.

const name = @import("name.zig");

pub const QualifiedName = name.QualifiedName;

/// Resolved column identity (post-bind). Used by planners / `expr_to_sources` style walks.
pub const Column = struct {
    table: ?QualifiedName = null,
    /// Table alias visible in the current scope (FROM alias).
    alias: []const u8 = "",
    name: []const u8,
};
