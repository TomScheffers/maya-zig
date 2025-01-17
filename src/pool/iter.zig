const std = @import("std");

/// A generic function that applies `func` to each element of `items` in parallel.
///
/// - `items` can be any slice (`[]T`) here; you could abstract further for a custom iterator.
/// - `func` is applied to each element in a worker thread.
fn worker(wg: *std.Thread.WaitGroup, data: []const u32, f: fn (u32) void) void {
    wg.start();
    defer wg.finish();

    // For each element in data, call f
    for (data) |value| {
        f(value);
    }
}

pub fn parallelForEach(items: []const u32, func: fn (u32) void) !void {
    // You can choose how many threads to spawn.
    // For simplicity, let's use the # of CPU cores:
    const cores = try std.Thread.getCpuCount();

    // If items is smaller than the # of cores, we'll just spawn min(cores, items.len) threads:
    const thread_count = if (items.len < cores) items.len else cores;

    // If there's no data, do nothing
    if (items.len == 0) return;

    var wait_group: std.Thread.WaitGroup = .{};

    // We'll divide the slice into `thread_count` sub-slices.
    const chunk_size = (items.len + thread_count - 1) / thread_count;
    // e.g. if 10 items, 4 threads -> chunk_size=3,3,3,1

    // Collect the spawned threads (so we can handle errors if needed):
    var thread_handles: []?std.Thread = try std.heap.page_allocator.alloc(?std.Thread, thread_count);
    defer std.heap.page_allocator.free(thread_handles);

    // Actually spawn the threads
    var start_index: usize = 0;
    for (0..thread_count) |i| {
        const end_index = @min(start_index + chunk_size, items.len);
        const slice_chunk = items[start_index..end_index];
        if (slice_chunk.len == 0) {
            // No more items? Let's just skip spawning an extra thread.
            thread_handles[i] = null; // or some sentinel
            break;
        }

        thread_handles[i] = try std.Thread.spawn(
            .{},
            worker,
            .{ &wait_group, slice_chunk, func },
        );
        start_index = end_index;
    }

    // Wait for all threads to finish
    wait_group.wait();
}

// We'll define a function that processes each element
fn doWork(val: u32) void {
    // For demonstration, just print
    std.debug.print("Thread {any} got value={d}\n", .{ std.Thread.Id, val });
    // In a real program, do CPU-bound work here, or accumulate results in a thread-safe data structure
}

//
// Demo usage
//
pub fn main() !void {
    var data = [_]u32{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 };

    try parallelForEach(data[0..], doWork);
    std.debug.print("All done!\n", .{});
}
