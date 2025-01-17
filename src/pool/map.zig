const std = @import("std");
const Thread = std.Thread;
const Timer = std.time.Timer;
const WaitGroup = std.Thread.WaitGroup;
const Pool = std.Thread.Pool;

pub fn load(comptime T: type, mem: []const T, comptime len: u32) @Vector(len, T) {
    const vt: type = comptime @Vector(len, T);
    var v: vt = @splat(0.0);
    inline for (0..len) |i| {
        v[i] = mem[i];
    }
    return v;
}

inline fn map_chunk(comptime T: type, from: []const T, to: []T, kernel: fn (u: T) callconv(.Inline) T) void {
    const len = @min(from.len, to.len);
    for (0..len) |i| {
        to[i] = kernel(from[i]);
    }
}

fn map(comptime number_of_threads: usize, comptime T: type, from: []T, to: []T, kernel: fn (u: T) callconv(.Inline) T) !void {
    const len = @min(from.len, to.len);
    const len_per_thread = len / number_of_threads;
    var threads: [number_of_threads]Thread = undefined;
    for (0..number_of_threads) |j| {
        threads[j] = try Thread.spawn(.{}, map_chunk, .{ T, from[j * len_per_thread .. (j + 1) * len_per_thread], to[j * len_per_thread .. (j + 1) * len_per_thread], kernel });
    }
    // join all threads
    for (threads) |thread| {
        thread.join();
    }
}

fn mapTp(comptime number_of_threads: usize, comptime T: type, from: []T, to: []T, kernel: fn (u: T) callconv(.Inline) T, pool: *std.Thread.Pool) !void {
    const len = @min(from.len, to.len);
    const len_per_thread = len / number_of_threads;

    var wait_group: WaitGroup = undefined;
    wait_group.reset();

    for (0..number_of_threads) |j| {
        pool.spawnWg(&wait_group, map_chunk, .{ T, from[j * len_per_thread .. (j + 1) * len_per_thread], to[j * len_per_thread .. (j + 1) * len_per_thread], kernel });
    }
    // join all threads
    pool.waitAndWork(&wait_group);
}

// https://zig.news/michalz/fast-multi-platform-simd-math-library-in-zig-2adn
// https://github.com/zig-gamedev/zig-gamedev/blob/main/libs/zmath/src/zmath.zig

inline fn testKernel(u: f32) f32 {
    return u * 12.0;
}

pub fn main() !void {
    const vs = comptime std.simd.suggestVectorLength(u32).?;
    std.debug.print("Vector legnth for cpu: {d}", .{vs});

    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const len = 300_000_000;
    const cores: comptime_int = 16;

    // Threadpool
    const opt = Pool.Options{
        .n_jobs = 4,
        .allocator = allocator,
    };
    var pool: Pool = undefined;
    _ = try pool.init(opt);
    defer pool.deinit();

    // Data init
    var from = try std.ArrayList(f32).initCapacity(allocator, len);
    defer from.deinit();
    var to = try std.ArrayList(f32).initCapacity(allocator, len);
    defer to.deinit();

    for (0..len) |i| {
        try from.append(@floatFromInt(i));
    }
    try to.appendNTimes(0.0, len);

    // Map threaded
    var timer = try Timer.start();
    for (0..10) |_| {
        try map(cores, f32, from.items, to.items, testKernel);
    }
    std.debug.print("\nTime for map function: {}ms", .{timer.read() / std.time.ns_per_ms});

    // Map threaded
    timer.reset();
    for (0..10) |_| {
        try mapTp(cores, f32, from.items, to.items, testKernel, &pool);
    }
    std.debug.print("\nTime for map tp function: {}ms", .{timer.read() / std.time.ns_per_ms});
}
