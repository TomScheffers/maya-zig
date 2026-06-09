//! Names and aliases for relations and columns.

pub const QualifiedName = struct {
    catalog: ?[]const u8 = null,
    schema: ?[]const u8 = null,
    relation: []const u8,
};

pub const Alias = struct {
    name: []const u8,
    /// Optional `AS (col1, col2, …)` names. Empty when not specified.
    column_names: []const []const u8 = &.{},
};
