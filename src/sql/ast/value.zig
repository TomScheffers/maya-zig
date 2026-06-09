//! Literal values in SQL expressions (sqlparser `Value` analogue).

pub const Value = union(enum) {
    null: void,
    boolean: bool,
    /// Unquoted numeric literal as written in SQL.
    number: []const u8,
    single_quoted: []const u8,
    /// `E'…'` escape string.
    escaped: []const u8,
};
