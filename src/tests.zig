const std = @import("std");
const parquet = @import("parquet/read.zig");
const bitmap = @import("core/bitmap.zig");
const Expr = @import("core/expr.zig").Expr;

test "bitmap extend" {
    const allocator = std.testing.allocator;

    const va: u64 = 0b1111100000;
    var ba = std.ArrayList(u64).init(allocator);
    try ba.append(va);
    var a = bitmap.Bitmap{ .data = ba, .len = 10 };
    defer a.deinit();

    const vb: u64 = 0b1010101010101010101010101010101010101010101010101010101010101010;
    var bb = std.ArrayList(u64).init(allocator);
    try bb.append(vb);

    const vb2: u64 = 0b111111111111111111111111111111111111111111111111111111111111111;
    try bb.append(vb2);
    var b = bitmap.Bitmap{ .data = bb, .len = 128 };
    defer b.deinit();

    try a.extend(&b);

    std.debug.print("\nA: {b} Size: {}", .{ a.data.items[0], a.len });
    std.debug.print("\nA: {b} Size: {}", .{ a.data.items[1], a.len });
    std.debug.print("\nA: {b} Size: {}", .{ a.data.items[2], a.len });

    const n = try a._not(allocator);
    defer n.deinit();

    const c = try a._and(n, allocator);
    defer c.deinit();
}

test "read" {
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
