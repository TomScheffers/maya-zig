const std = @import("std");

pub const ThreadSafeAllocator = struct {
    backing: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},

    pub fn allocator(self: *ThreadSafeAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = tsAlloc,
        .resize = tsResize,
        .free = tsFree,
        .remap = tsRemap,
    };

    fn tsAlloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *ThreadSafeAllocator = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.backing.rawAlloc(len, ptr_align, ret_addr);
    }

    fn tsResize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *ThreadSafeAllocator = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.backing.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn tsRemap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *ThreadSafeAllocator = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.backing.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn tsFree(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *ThreadSafeAllocator = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        self.backing.rawFree(buf, buf_align, ret_addr);
    }
};
