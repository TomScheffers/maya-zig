const std = @import("std");
const varint = @import("../utils/varint.zig");
const LargeString = @import("../utils/string.zig").LargeString;

fn sliceToU64(buf: []u8) !u64 {
    switch (buf.len) {
        1 => {
            return @as(u64, @intCast(buf[0]));
        },
        2 => {
            const vbuf = @as(*[2]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u16, &vbuf, std.builtin.Endian.little)));
        },
        3 => {
            const vbuf = @as(*[3]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u24, &vbuf, std.builtin.Endian.little)));
        },
        4 => {
            const vbuf = @as(*[4]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u32, &vbuf, std.builtin.Endian.little)));
        },
        5 => {
            const vbuf = @as(*[5]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u40, &vbuf, std.builtin.Endian.little)));
        },
        6 => {
            const vbuf = @as(*[6]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u48, &vbuf, std.builtin.Endian.little)));
        },
        7 => {
            const vbuf = @as(*[7]u8, @ptrCast(buf.ptr)).*;
            return @as(u64, @intCast(std.mem.readInt(u56, &vbuf, std.builtin.Endian.little)));
        },
        8 => {
            const vbuf = @as(*[8]u8, @ptrCast(buf.ptr)).*;
            return std.mem.readInt(u64, &vbuf, std.builtin.Endian.little);
        },
        else => {
            unreachable;
        },
    }
}

// TODO: Comptime slice to uint

// fn sliceToUInt(buf: []u8, comptime T: type) !T {
//     const size = comptime @sizeOf(T);
//     if (buf.len > size) {
//         return error.BufferTooLarge;
//     } else if (buf.len == 1) {
//         return @as(T, @intCast(buf[0]));
//     } else {
//         switch (buf.len) {
//             inline else => |x| {
//                 const vbuf = @as(*[x]u8, @ptrCast(buf.ptr)).*;
//                 return std.mem.readInt(T, &vbuf, std.builtin.Endian.little);
//             },
//         }
//     }
// }

pub fn bitpackDecode(buf: []u8, num_bits: u5, length: usize, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    var data = try std.ArrayList(T).initCapacity(allocator, length);
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    if (num_bits * length / 8 > buf.len) return error.BufferTooSmall;

    if (num_bits % 8 == 0) {
        const bytes = num_bits / 8;
        var i: usize = 0;
        while (i < length * bytes) : (i += bytes) {
            const v = try sliceToU64(buf[i..(i + bytes)]);
            try data.append(@intCast(v));
        }
        return data;
    } else {
        const msk: T = if (T == u1) 1 else std.math.pow(T, 2, @intCast(num_bits)) - 1;
        var v = try sliceToU64(buf[0..@min(buf.len, 8)]); // Read first 8 bytes as u64
        var i: usize = 0;
        while (i < length) : (i += 1) {
            const start_bit = (i * num_bits);
            if ((start_bit % 64) + num_bits >= 64) { // We will overflow 32 bits, so reset v
                const start_byte = start_bit / 8;
                const end_byte = @min(buf.len, start_byte + 8);
                v = try sliceToU64(buf[start_byte..end_byte]);
                v = (v >> @intCast(start_bit - start_byte * 8));
            }
            try data.append(@intCast(v & msk));
            v = (v >> num_bits);
        }
        return data;
    }
}

pub fn rleDecode(buf: []u8, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    const size = @sizeOf(T);
    var data = try std.ArrayList(T).initCapacity(allocator, num_values);
    var i: usize = 0;
    var j: usize = 0;
    std.debug.print("\nBuffer len {} Num values {}", .{ buf.len, num_values });
    while (j < num_values) {
        // Run length
        const vi = varint.decodeVarint(buf[i..]);
        const rl: usize = vi.result >> 1;
        i += vi.bytes;
        std.debug.print("\nRL {} {}", .{ rl, vi.bytes });

        // Calculate repeated value
        const vbuf = @as(*[size]u8, @ptrCast(buf[(i)..(i + size)].ptr)).*;
        const v = std.mem.readInt(T, &vbuf, std.builtin.Endian.little);
        try data.appendNTimes(v, rl);
        i += size;
        j += rl;
    }
    return data;
}

pub fn rleHybridDecode(buf: []u8, num_bits: u5, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.ArrayList(T) {
    // Read varint to determine if we are bitpacking or rle
    const vi = varint.decodeVarint(buf);
    if (num_bits == 0) {
        var decoded = try std.ArrayList(T).initCapacity(allocator, num_values);
        try decoded.appendNTimes(0, num_values);
        return decoded;
    } else if (vi.result & 1 == 1) {
        // bitpacking
        const bytes: usize = (vi.result >> 1) * num_bits; // Bytes is lower than expected? Weird behavior
        std.debug.print("\nLengths {} {} {}", .{ vi.result >> 1, num_values, bytes });
        const decoded = try bitpackDecode(buf[(vi.bytes)..], num_bits, num_values, T, allocator);
        return decoded;
    } else {
        // rle encoding
        return rleDecode(buf, num_values, T, allocator);
    }
}

pub fn rleBitmapDecode(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.ArrayList(u64) {
    // Read varint to determine if we are bitpacking or rle
    const vi = varint.decodeVarint(buf);
    const size = (num_values + 63) / 64;
    if (vi.result & 1 == 1) {
        // bitpacking
        var decoded = try std.ArrayList(u64).initCapacity(allocator, size);
        var i: usize = vi.bytes;
        while (i < buf.len) : (i += 8) {
            const v = try sliceToU64(buf[i..@min(buf.len, i + 8)]);
            try decoded.append(v);
        }
        return decoded;
    } else {
        // rle encoding
        const rle = try rleDecode(buf, num_values, u8, allocator);
        defer rle.deinit();

        // Bitpacking into u64
        var decoded = try std.ArrayList(u64).initCapacity(allocator, size);

        var pack: u64 = 0;
        var bit: u7 = 0;
        for (rle.items, 0..) |boolean, i| {
            if (boolean != 0) {
                pack |= @as(u64, 1) << @intCast(bit);
            }

            bit += 1;
            if (bit == 64 or i == rle.items.len - 1) {
                try decoded.append(pack);
                pack = 0;
                bit = 0;
            }
        }
        return decoded;
    }
}

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

test "bitpacking" {
    // Test data: 0-7 with bit width 3
    // 0: 000
    // 1: 001
    // 2: 010
    // 3: 011
    // 4: 100
    // 5: 101
    // 6: 110
    // 7: 111
    const num_bits = 3;
    const length = 16;
    // encoded: 0b10001000u8, 0b11000110, 0b11111010
    var data = [_]u8{ 0b10001000, 0b11000110, 0b11111010, 0b10001000, 0b11000110, 0b11111010 };
    const exp = [_]u64{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7 };

    const allocator = std.testing.allocator;

    const decoded = try bitpackDecode(&data, num_bits, length, u64, allocator);
    defer decoded.deinit();

    std.debug.print("Decoded {d}", .{decoded.items});

    try std.testing.expect(std.mem.eql(u64, decoded.items, &exp));
}
