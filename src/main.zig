const std = @import("std");
const parquet = @import("parquet/read.zig");
const bitmap = @import("core/bitmap.zig");
const Expr = @import("core/expr.zig").Expr;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const path = "data/stock_current/org_key=0/file.parquet";

    // Demo 1: Standard parquet reading (optimized approach)
    std.debug.print("=== Optimized Parquet Reading ===\n", .{});

    var frame = try parquet.readParquetOld(path, allocator);
    defer frame.deinit();

    var frame_new = try parquet.readParquet(path, allocator);
    defer frame_new.deinit();

    // Print frame info
    std.debug.print("New ParquetReader succeeded! Frame loaded.\n", .{});
    _ = try frame.print(allocator);

    // Demo 2: Add expression column
    std.debug.print("\n=== Adding Expression Column ===\n", .{});
    const e = Expr.column("technical").add(&Expr.column("org_key"));
    try frame.with_column("technical_plus_org", e, allocator);

    std.debug.print("Frame with new expression column:\n", .{});
    _ = try frame.print(allocator);

    // Demo 3: Try selective reading (experimental - may have buffer issues)
    std.debug.print("\n=== Experimental Selective Reading ===\n", .{});

    // First, safely get column names
    const column_names = parquet.getParquetColumns(path, allocator) catch |err| {
        std.debug.print("Could not get column names: {}\n", .{err});
        return;
    };
    defer {
        for (column_names.items) |name| {
            allocator.free(name);
        }
        column_names.deinit();
    }

    std.debug.print("Available columns:\n", .{});
    for (column_names.items, 0..) |name, i| {
        std.debug.print("  {d}: {s}\n", .{ i, name });
    }

    // Try selective reading if we have the expected columns
    if (column_names.items.len >= 2) {
        std.debug.print("\nAttempting selective reading...\n", .{});
        const selected_columns = [_][]const u8{ "technical", "org_key" };
        var frame_selective = parquet.readParquetSelective(path, &selected_columns, allocator) catch |err| {
            std.debug.print("Selective reading failed (expected): {}\n", .{err});
            std.debug.print("This is normal - we're debugging the buffer issue\n", .{});
            return;
        };
        defer frame_selective.deinit();

        std.debug.print("Selective reading succeeded!\n", .{});
        _ = try frame_selective.print(allocator);
    }
}
