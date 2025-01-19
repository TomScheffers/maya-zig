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

fn decodeFloatPack(comptime T: type, comptime size: usize, comptime chunk_size: usize, input: *[chunk_size * size]u8, output: *[chunk_size]T) void {
    output.* = @bitCast(input.*);
}

pub fn plainDecodeFloat(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;
    const num_values: usize = buf.len / size;
    var result = try allocator.alloc(T, num_values);

    // Why not memcpy directly into result?
    // const result_as_bytes = std.mem.asBytes(result);
    // const result_as_slice = std.mem.bytesAsSlice(u8, result_as_bytes);
    // std.debug.print("Buf len {} result bytes len {} result slice len {}", .{ buf.len, result_as_bytes.len, result_as_slice.len });
    // @memcpy(result_as_slice[0..], buf);

    const chunk_size = 1024;
    for (0..num_values / chunk_size) |c| {
        decodeFloatPack(T, size, chunk_size, buf[c * chunk_size * size .. (c + 1) * chunk_size * size][0 .. chunk_size * size], result[c * chunk_size .. (c + 1) * chunk_size][0..chunk_size]);
    }

    const remainder = num_values % chunk_size;
    var byte_offset = buf.len - remainder * size;
    for (num_values - remainder..num_values) |i| {
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
        result[i] = try LargeString.init(buf[offset .. offset + bytes], allocator);
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
