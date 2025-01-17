const std = @import("std");
const parquet = @import("parquet/read.zig");
const enc = @import("parquet/encodings/mod.zig");
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

const time = std.time;
const Instant = time.Instant;

test "bitpackTime" {
    // const RndGen = std.rand.DefaultPrng;
    // var rnd = RndGen.init(0);
    const allocator = std.testing.allocator;
    for (0..25) |num_bits| {
        const num_values = 1_000_000;
        const num_bytes = num_values * num_bits / 8;
        const buf = try allocator.alloc(u8, num_bytes);
        defer allocator.free(buf);

        const start = try Instant.now();
        for (0..10) |_| {
            const decoded = try enc.bitpack.bitpackDecode(buf, @intCast(num_bits), num_values, u32, allocator);
            defer decoded.deinit();
        }
        const end = try Instant.now();
        const elapsed1: f64 = @floatFromInt(end.since(start));
        std.debug.print("\nTime elapsed for num_bits {d} and buf len {d} is: {d:.3}ms\n", .{ num_bits, buf.len, elapsed1 / time.ns_per_ms });
    }
}

test "bitpacking" {
    // Test data: 0-7 with bit width 3
    // 0: 000
    // 1: 001
    // 2: 010
    // 3: 011
    // 4: 100
    // 5: 101
    // 6: 110
    // 7: 111
    const num_bits: u5 = 3;
    const length = 16;
    // encoded: 0b10001000u8, 0b11000110, 0b11111010
    var data = [_]u8{ 0b10001000, 0b11000110, 0b11111010, 0b10001000, 0b11000110, 0b11111010 };
    const exp = [_]u64{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7 };

    const allocator = std.testing.allocator;

    const decoded = try enc.bitpack.bitpackDecodeSIMD(&data, num_bits, length, u64, allocator);
    defer decoded.deinit();

    std.debug.print("Decoded {d}", .{decoded.items});

    try std.testing.expect(std.mem.eql(u64, decoded.items, &exp));
}

test "read" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // const allocator = std.testing.allocator;

    //const path = "data/stock/store_key=1/00000000.parquet";
    const path = "data/stock_current/org_key=0/file.parquet";

    const start = try Instant.now();
    const frame = try parquet.readParquet(path, allocator);
    const end = try Instant.now();
    const elapsed: f64 = @floatFromInt(end.since(start));
    // Print frame
    try frame.print(allocator);
    std.debug.print("\nTime elapsed for parquet reading is: {d:.3}ms\n", .{elapsed / time.ns_per_ms});
}

test "groupby" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // const allocator = std.testing.allocator;

    //const path = "data/stock/store_key=1/00000000.parquet";
    const path = "data/stock_current/org_key=0/file.parquet";
    var frame = try parquet.readParquet(path, allocator);

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
