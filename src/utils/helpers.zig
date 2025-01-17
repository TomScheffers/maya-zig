const std = @import("std");
const s8 = struct { left: u4, right: u4 };

pub fn splitU8(b: u8) s8 {
    return s8{ .left = @intCast((b >> 4) & 0xF), .right = @intCast((b >> 0) & 0xF) }; // shift by 0 not needed, of course, just stylistic
}

pub fn sliceToInt(s: []u8) u64 { // Little Endian read u64
    var result: u64 = 0;
    var base: u64 = 0;
    for (s) |v| {
        base = if (base == 0) 1 else base * 0x100;
        result += v * base;
    }
    return result;
}

pub fn sliceToUInt(buf: []u8, comptime T: type) !T {
    const size = comptime @sizeOf(T);
    if (buf.len == size) return std.mem.bytesToValue(T, buf);
    if (buf.len > size) return error.BufferTooLarge;
    switch (buf.len) {
        0 => return @as(T, 0),
        1 => return @as(T, @intCast(buf[0])),
        2 => {
            const vbuf = @as(*[2]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u16, &vbuf, std.builtin.Endian.little)));
        },
        3 => {
            const vbuf = @as(*[3]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u24, &vbuf, std.builtin.Endian.little)));
        },
        4 => {
            const vbuf = @as(*[4]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u32, &vbuf, std.builtin.Endian.little)));
        },
        5 => {
            const vbuf = @as(*[5]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u40, &vbuf, std.builtin.Endian.little)));
        },
        6 => {
            const vbuf = @as(*[6]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u48, &vbuf, std.builtin.Endian.little)));
        },
        7 => {
            const vbuf = @as(*[7]u8, @ptrCast(buf.ptr)).*;
            return @as(T, @intCast(std.mem.readInt(u56, &vbuf, std.builtin.Endian.little)));
        },
        else => {
            unreachable;
        },
    }
}
