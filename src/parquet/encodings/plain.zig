const std = @import("std");
const varint = @import("../../utils/varint.zig");
const LargeString = @import("../../utils/string.zig").LargeString;
const helpers = @import("../../utils/helpers.zig");

pub fn plainDecodeInt(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;
    const num_values: usize = buf.len / size;
    var result = try allocator.alloc(T, num_values);
    var byte_offset: usize = 0;
    for (0..num_values) |i| {
        result[i] = std.mem.readInt(T, buf[byte_offset .. byte_offset + size][0..size], std.builtin.Endian.little);
        byte_offset += size;
    }
    return std.ArrayList(T).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeFloat(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;
    const num_values: usize = buf.len / size;
    var result = try allocator.alloc(T, num_values);
    var byte_offset: usize = 0;
    for (0..num_values) |i| {
        result[i] = @bitCast(buf[byte_offset .. byte_offset + size][0..size].*);
        byte_offset += size;
    }
    return std.ArrayList(T).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.ArrayList(LargeString) {
    var result = try allocator.alloc(LargeString, num_values);
    var offset: usize = 0;

    for (0..num_values) |i| {
        // Find amount of bytes
        const vbuf = @as(*[4]u8, @ptrCast(buf[offset .. offset + 4].ptr)).*;
        const bytes = std.mem.readInt(u32, &vbuf, std.builtin.Endian.little);
        offset += 4;

        // Append bytes
        result[i] = try LargeString.init(buf[(offset)..(offset + bytes)], allocator);
        offset += bytes;

        if (offset == buf.len) break; // TODO: Remove this? Num values is not correct when null values are present??
    }
    return std.ArrayList(LargeString).fromOwnedSlice(allocator, result[0..]);
}

pub fn plainDecodeFixedBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.ArrayList(LargeString) {
    const bytes = buf.len / num_values;
    var result = try allocator.alloc(LargeString, num_values);
    var offset: usize = 0;
    for (0..num_values) |i| {
        result[i] = try LargeString.init(buf[offset .. offset + bytes], allocator);
        offset += bytes;
    }
    return std.ArrayList(LargeString).fromOwnedSlice(allocator, result[0..]);
}
