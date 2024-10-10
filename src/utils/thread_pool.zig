const std = @import("std");

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

pub fn printPrime(wait_group: *WaitGroup, start: usize, end: usize) void {
    wait_group.start();
    defer wait_group.finish();

    for (start..end) |value| {
        if (value == 0) {
            continue;
        }

        var is_value_prime = true;
        var i: u64 = 2;
        while (i < value) : (i += 1) {
            if (value % i == 0) {
                is_value_prime = false;
                break;
            }
        }
        if (is_value_prime) std.debug.print("\nFound prime {}", .{value});
    }
}

test "threadpool" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var thread_pool: Pool = undefined;
    try thread_pool.init(Pool.Options{ .n_jobs = 8, .allocator = allocator });
    defer thread_pool.deinit();

    var wait_group: WaitGroup = undefined;
    wait_group.reset();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try thread_pool.spawn(printPrime, .{ &wait_group, i * 10, i * 10 + 10 });
    }

    thread_pool.waitAndWork(&wait_group);
}
