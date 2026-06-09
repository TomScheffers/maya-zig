//! Maya query engine library root.
//!
//! Layout:
//!   core/     columnar types (frame, series, expressions)
//!   io/       data sources (parquet today, iceberg later)
//!   sql/      SQL frontend (libpg_query + Maya AST)
//!   util/     shared helpers

pub const core = struct {
    pub const frame = @import("core/frame.zig");
    pub const series = @import("core/series.zig");
    pub const expr = @import("core/expr.zig");
    pub const datatype = @import("core/datatype.zig");
    pub const bitmap = @import("core/bitmap.zig");
};

pub const io = struct {
    pub const parquet = @import("io/parquet/read.zig");
};

pub const sql = struct {
    pub const pg_query = @import("sql/pg_query.zig");
};

pub const util = struct {
    pub const helpers = @import("util/helpers.zig");
};

// Re-export commonly used modules at the package root.
pub const frame = core.frame;
pub const series = core.series;
pub const Expr = core.expr.Expr;
pub const parquet = io.parquet;

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
