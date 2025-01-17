const std = @import("std");
const varint = @import("../../utils/varint.zig");
const LargeString = @import("../../utils/string.zig").LargeString;
const helpers = @import("../../utils/helpers.zig");
const bitpack = @import("bitpack.zig");

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
        const decoded = try bitpack.bitpackDecode(buf[(vi.bytes)..], num_bits, num_values, T, allocator);
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
            const v = try helpers.sliceToUInt(buf[i..@min(buf.len, i + 8)], u64);
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
