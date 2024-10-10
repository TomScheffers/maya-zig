const std = @import("std");

pub fn readZstd(buf: []u8, allocator: std.mem.Allocator) ![]u8 {
    return std.compress.zstd.decompress.decodeAlloc(allocator, buf, false, 8 * 1024 * 1024);
}
