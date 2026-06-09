//! Expression tree walks (mirrors `expr_to_sources` / `expr_to_column` in mayadb `graph.rs`).
//!
//! Implement these as you wire the planner; stubs return empty / errors for now.

const std = @import("std");

const column = @import("column.zig");
const expr_mod = @import("expr.zig");

pub const Column = column.Column;
pub const Expr = expr_mod.Expr;

pub const AnalysisError = error{
    NotAColumn,
    UnsupportedExpr,
};

/// Collect column references used by an expression (for filter pushdown, join keys, etc.).
pub fn referencedColumns(_: *const Expr, _: std.mem.Allocator) AnalysisError![]const Column {
    // TODO: walk tree like mayadb `expr_to_sources`
    return &[_]Column{};
}

/// Extract a single column when the expression is a bare or qualified identifier.
pub fn exprToColumn(e: *const Expr) AnalysisError!Column {
    return switch (e.*) {
        .column => |cref| switch (cref) {
            .bare => |name| .{ .name = name },
            .qualified => |parts| {
                if (parts.len == 0) return error.NotAColumn;
                if (parts.len == 1) return .{ .name = parts[0] };
                return .{
                    .alias = parts[parts.len - 2],
                    .name = parts[parts.len - 1],
                };
            },
        },
        else => error.NotAColumn,
    };
}
