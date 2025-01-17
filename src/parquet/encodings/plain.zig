const std = @import("std");
const varint = @import("../../utils/varint.zig");
const LargeString = @import("../../utils/string.zig").LargeString;
const helpers = @import("../../utils/helpers.zig");

pub fn plainDecodeInt(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;

    const capacity: usize = buf.len / size;
    var data = try std.ArrayList(T).initCapacity(allocator, capacity);

    var i: usize = 0;
    while (i < buf.len) : (i += size) {
        const vbuf = @as(*[size]u8, @ptrCast(buf[(i)..(i + size)].ptr)).*;
        const v = std.mem.readInt(T, &vbuf, std.builtin.Endian.little);
        try data.append(v);
    }
    return data;
}

pub fn plainDecodeFloat(buf: []u8, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    if (buf.len % size > 0) return error.InvalidBufferLength;

    const capacity: usize = buf.len / size;
    var data = try std.ArrayList(T).initCapacity(allocator, capacity);

    var i: usize = 0;
    while (i < buf.len) : (i += size) {
        const vbuf = @as(*[size]u8, @ptrCast(buf[(i)..(i + size)].ptr)).*;
        const v: T = @bitCast(vbuf);
        try data.append(v);
    }
    return data;
}

pub fn plainDecodeBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.ArrayList(LargeString) {
    var data = try std.ArrayList(LargeString).initCapacity(allocator, num_values);
    var offset: usize = 0;
    while (offset < buf.len) {
        // Find amount of bytes
        const vbuf = @as(*[4]u8, @ptrCast(buf[(offset)..(offset + 4)].ptr)).*;
        const bytes = std.mem.readInt(u32, &vbuf, std.builtin.Endian.little);
        offset += 4;

        // Append bytes
        const s = try LargeString.init(buf[(offset)..(offset + bytes)], allocator);
        try data.append(s);
        offset += bytes;
    }
    return data;
}

pub fn plainDecodeFixedBytes(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.ArrayList(LargeString) {
    const bytes = buf.len / num_values;
    var data = try std.ArrayList(LargeString).initCapacity(allocator, num_values);
    var i: usize = 0;
    while (i < buf.len) : (i += bytes) {
        const s = try LargeString.init(buf[(i)..(i + bytes)], allocator);
        try data.append(s);
    }
    return data;
}
