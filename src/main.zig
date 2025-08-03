const std = @import("std");
const parquet = @import("parquet/read.zig");
const bitmap = @import("core/bitmap.zig");
const Expr = @import("core/expr.zig").Expr;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const path = "data/stock_current/org_key=0/file.parquet";

    // Demo 1: List available columns
    std.debug.print("=== Available Columns ===\n", .{});
    const column_names = try parquet.getParquetColumns(path, allocator);
    defer {
        for (column_names.items) |name| {
            allocator.free(name);
        }
        column_names.deinit();
    }

    for (column_names.items, 0..) |name, i| {
        std.debug.print("{d}: {s}\n", .{ i, name });
    }

    // Demo 2: Read only specific columns (much more memory efficient!)
    std.debug.print("\n=== Reading Selective Columns ===\n", .{});
    const selected_columns = [_][]const u8{ "technical", "org_key" };
    var frame_selective = try parquet.readParquetSelective(path, &selected_columns, allocator);
    defer frame_selective.deinit();

    std.debug.print("Selective frame with {} columns:\n", .{selected_columns.len});
    _ = try frame_selective.print(allocator);

    // Demo 3: Compare with reading all columns
    std.debug.print("\n=== Performance Comparison ===\n", .{});

    const start_selective = std.time.nanoTimestamp();
    var frame_sel_perf = try parquet.readParquetSelective(path, &selected_columns, allocator);
    const end_selective = std.time.nanoTimestamp();
    defer frame_sel_perf.deinit();

    const start_full = std.time.nanoTimestamp();
    var frame_full = try parquet.readParquet(path, allocator);
    const end_full = std.time.nanoTimestamp();
    defer frame_full.deinit();

    const selective_time: f64 = @floatFromInt(end_selective - start_selective);
    const full_time: f64 = @floatFromInt(end_full - start_full);

    std.debug.print("Selective reading time: {d:.3}ms\n", .{selective_time / 1_000_000});
    std.debug.print("Full file reading time: {d:.3}ms\n", .{full_time / 1_000_000});
    std.debug.print("Performance improvement: {d:.1}x faster\n", .{full_time / selective_time});

    // Demo 4: Advanced usage with ParquetReader for multiple operations
    std.debug.print("\n=== Advanced Usage with ParquetReader ===\n", .{});
    var reader = try parquet.ParquetReader.init(path, allocator);
    defer reader.deinit();

    // Read specific row group with specific columns
    const chunk = try reader.readRowGroupSelective(0, &selected_columns);
    defer chunk.deinit();

    std.debug.print("First row group with selected columns:\n", .{});
    for (chunk.columns.items) |column| {
        std.debug.print("Column: {s}, Length: {d}\n", .{ column.name, column.len() });
    }

    // Evaluate expression on selective data
    const e = Expr.column("technical").add(&Expr.column("org_key"));
    try frame_selective.with_column("technical_plus_org", e, allocator);

    std.debug.print("\n=== Frame with Expression ===\n", .{});
    _ = try frame_selective.print(allocator);
}
