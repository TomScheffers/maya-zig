const std = @import("std");
const parquet = @import("parquet/read.zig");
const bitmap = @import("core/bitmap.zig");
const Expr = @import("core/expr.zig").Expr;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // const allocator = std.testing.allocator;

    //const path = "data/stock/store_key=1/00000000.parquet";
    const path = "data/stock_current/org_key=0/file.parquet";
    var frame = try parquet.readParquet(path, allocator);

    // Print frame
    _ = try frame.print(allocator);

    // Evaluate expression
    const e = Expr.column("technical").add(&Expr.column("org_key"));
    try frame.with_column("technical_p1", e, allocator);

    // Print frame
    _ = try frame.print(allocator);

    // Group by
    var names = std.ArrayList([]const u8).init(allocator);
    defer names.deinit();

    try names.append("store_key");
    _ = try frame.group_by(names, allocator);
}
