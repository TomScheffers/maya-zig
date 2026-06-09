const std = @import("std");
const varint = @import("../../../util/varint.zig");
const LargeString = @import("../../../util/string.zig").LargeString;
const helpers = @import("../../../util/helpers.zig");

pub fn plainDecodeInt(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;
    var result = try allocator.alloc(T, buf.len / size);
    const buf_as_slice = std.mem.bytesAsSlice(T, buf);
    @memcpy(result, buf_as_slice);
    return std.array_list.Managed(T).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeFloat(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;
    var result = try allocator.alloc(T, buf.len / size);
    const buf_as_slice = std.mem.bytesAsSlice(T, buf);
    @memcpy(result, buf_as_slice);
    return std.array_list.Managed(T).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.array_list.Managed(LargeString) {
    var result = try allocator.alloc(LargeString, num_values);
    var offset: usize = 0;

    for (0..num_values) |i| {
        // Find amount of bytes
        const vbuf = @as(*[4]u8, @ptrCast(buf[offset .. offset + 4].ptr)).*;
        const bytes = std.mem.readInt(u32, &vbuf, std.builtin.Endian.little);
        offset += 4;
        // std.debug.print("Bytes: {d}\n", .{bytes});

        // Append bytes
        result[i] = try LargeString.init(buf[offset .. offset + bytes], allocator);
        offset += bytes;

        if (offset == buf.len) break; // TODO: Remove this? Num values is not correct when null values are present??
    }
    return std.array_list.Managed(LargeString).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeFixedBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.array_list.Managed(LargeString) {
    const bytes = buf.len / num_values;
    var result = try allocator.alloc(LargeString, num_values);
    var offset: usize = 0;
    for (0..num_values) |i| {
        result[i] = try LargeString.init(buf[offset .. offset + bytes], allocator);
        offset += bytes;
    }
    return std.array_list.Managed(LargeString).fromOwnedSlice(allocator, result[0..]);
}
