const std = @import("std");
const time = std.time;
const Io = std.Io;
const io = std.testing.io;
const parquet = @import("io/parquet/read.zig");
const enc = @import("io/parquet/encodings/mod.zig");
const bitmap = @import("core/bitmap.zig");
const Expr = @import("core/expr.zig").Expr;

fn monotonicNow() Io.Clock.Timestamp {
    return Io.Clock.Timestamp.now(io, .awake);
}

fn elapsedNs(start: Io.Clock.Timestamp, end: Io.Clock.Timestamp) i96 {
    return Io.Clock.Timestamp.durationTo(start, end).raw.toNanoseconds();
}

test "bitmap extend" {
    const allocator = std.testing.allocator;

    const va: u64 = 0b1111100000;
    var ba = std.array_list.Managed(u64).init(allocator);
    try ba.append(va);
    var a = bitmap.Bitmap{ .data = ba, .len = 10 };
    defer a.deinit();

    const vb: u64 = 0b1010101010101010101010101010101010101010101010101010101010101010;
    var bb = std.array_list.Managed(u64).init(allocator);
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

test "bitpackTime" {
    // const RndGen = std.rand.DefaultPrng;
    // var rnd = RndGen.init(0);
    const allocator = std.testing.allocator;
    for (0..25) |num_bits| {
        const num_values = 1_000_000;
        const num_bytes = num_values * num_bits / 8;
        const buf = try allocator.alloc(u8, num_bytes);
        defer allocator.free(buf);

        const start = monotonicNow();
        for (0..10) |_| {
            const decoded = try enc.bitpack.bitpackDecode(buf, @intCast(num_bits), num_values, u32, allocator);
            defer decoded.deinit();
        }
        const end = monotonicNow();
        const elapsed1: f64 = @floatFromInt(elapsedNs(start, end));
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

    const decoded = try enc.bitpack.bitpackDecode(&data, num_bits, length, u64, allocator);
    defer decoded.deinit();

    std.debug.print("Decoded {any}", .{decoded.items});

    try std.testing.expect(std.mem.eql(u64, decoded.items, &exp));
}

test "bitpack decodeInto" {
    const num_bits: usize = 3;
    const length = 16;
    var data = [_]u8{ 0b10001000, 0b11000110, 0b11111010, 0b10001000, 0b11000110, 0b11111010 };
    const exp = [_]u64{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7 };
    var out: [16]u64 = undefined;
    try enc.bitpack.bitpackDecodeInto(&data, num_bits, length, u64, &out);
    try std.testing.expectEqualSlices(u64, &exp, &out);

    // Byte-aligned width: one u8 per value
    const bytes = [_]u8{ 0x10, 0x20, 0x30 };
    var out8: [3]u32 = undefined;
    try enc.bitpack.bitpackDecodeInto(&bytes, 8, 3, u32, &out8);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0x10, 0x20, 0x30 }, &out8);
}

fn fillBufWithPattern(buf: []u8, pattern: []const u8) void {
    var off: usize = 0;
    while (off < buf.len) {
        const n = @min(pattern.len, buf.len - off);
        @memcpy(buf[off..][0..n], pattern[0..n]);
        off += n;
    }
}

// Microbenchmark for bitpack.zig — run: zig test src/tests.zig -O ReleaseFast --test-filter "bitpack perf"
test "bitpack perf" {
    const allocator = std.heap.page_allocator;
    const pattern = [_]u8{ 0b10001000, 0b11000110, 0b11111010 };

    // Scalar path (same pattern family as "bitpacking", u32)
    {
        const num_bits: usize = 3;
        const num_values: usize = 1_000_000;
        const buf_len = num_values * num_bits / 8;
        const buf = try allocator.alloc(u8, buf_len);
        defer allocator.free(buf);
        fillBufWithPattern(buf, &pattern);
        for (0..2) |_| {
            const d = try enc.bitpack.bitpackDecode(buf, num_bits, num_values, u32, allocator);
            d.deinit();
        }
        const iters: usize = 15;
        const start = monotonicNow();
        for (0..iters) |_| {
            const d = try enc.bitpack.bitpackDecode(buf, num_bits, num_values, u32, allocator);
            d.deinit();
        }
        const elapsed = elapsedNs(start, monotonicNow());
        std.debug.print(
            "\n[scalar u32] num_bits=3 {d} iters x 1M vals: {d:.3} ms total\n",
            .{ iters, @as(f64, @floatFromInt(elapsed)) / time.ns_per_ms },
        );
    }

    // u64 + non-multiple-of-chunk length (exercises residual path)
    {
        const num_bits: usize = 3;
        const num_values: usize = 1_000_003;
        const buf_len = (num_values * num_bits + 7) / 8;
        const buf = try allocator.alloc(u8, buf_len);
        defer allocator.free(buf);
        fillBufWithPattern(buf, &pattern);
        for (0..2) |_| {
            const d = try enc.bitpack.bitpackDecode(buf, num_bits, num_values, u64, allocator);
            d.deinit();
        }
        const iters: usize = 20;
        const start = monotonicNow();
        for (0..iters) |_| {
            const d = try enc.bitpack.bitpackDecode(buf, num_bits, num_values, u64, allocator);
            d.deinit();
        }
        const elapsed = elapsedNs(start, monotonicNow());
        std.debug.print(
            "\n[u64 residual] num_bits=3 {d} iters x 1M003 vals: {d:.3} ms total\n",
            .{ iters, @as(f64, @floatFromInt(elapsed)) / time.ns_per_ms },
        );
    }
}

fn yellowTripdataParquetPath(allocator: std.mem.Allocator) ![]const u8 {
    const file_name = "yellow_tripdata_2026-01.parquet";
    const rel_attempts: []const []const []const u8 = &.{
        &.{ "data", file_name },
        &.{ "maya-zig", "data", file_name },
    };
    for (rel_attempts) |parts| {
        const p = try std.fs.path.join(allocator, parts);
        std.Io.Dir.cwd().access(io, p, .{}) catch continue;
        return p;
    }
    return error.MissingYellowTripdataFixture;
}

test "read" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // readParquet uses cwd-relative paths; try repo-root and parent-folder layouts.
    const path = try yellowTripdataParquetPath(allocator);

    const start = monotonicNow();
    const frame = try parquet.readParquet(io, path, allocator);
    const end = monotonicNow();
    const elapsed: f64 = @floatFromInt(elapsedNs(start, end));
    _ = try frame.print(allocator);
    std.debug.print("\nTime elapsed for parquet reading is: {d:.3}s\n", .{elapsed / time.ns_per_s});
}

test "groupby" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const path = "data/stock_current/org_key=0/file.parquet";
    std.Io.Dir.cwd().access(io, path, .{}) catch return error.SkipZigTest;

    var frame = try parquet.readParquet(io, path, allocator);

    // Evaluate expression
    const e = Expr.column("technical").add(&Expr.column("org_key"));
    try frame.with_column("technical_p1", e, allocator);

    // Print frame
    _ = try frame.print(allocator);

    // Group by
    var names = std.array_list.Managed([]const u8).init(allocator);
    defer names.deinit();

    try names.append("store_key");
    _ = try frame.group_by(names, allocator);
}
