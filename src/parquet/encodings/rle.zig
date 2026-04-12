const std = @import("std");
const varint = @import("../../utils/varint.zig");
const LargeString = @import("../../utils/string.zig").LargeString;
const helpers = @import("../../utils/helpers.zig");
const bitpack = @import("bitpack.zig");

pub fn rleDecode(buf: []u8, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    const size = @sizeOf(T);
    var data = try std.array_list.Managed(T).initCapacity(allocator, num_values);
    var i: usize = 0;
    var j: usize = 0;
    while (j < num_values) {
        const vi = varint.decodeVarint(buf[i..]);
        const rl: usize = vi.result >> 1;
        i += vi.bytes;

        const vbuf = @as(*[size]u8, @ptrCast(buf[(i)..(i + size)].ptr)).*;
        const v = std.mem.readInt(T, &vbuf, std.builtin.Endian.little);
        try data.appendNTimes(v, rl);
        i += size;
        j += rl;
    }
    return data;
}

pub fn rleHybridDecode(buf: []u8, num_bits: u5, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    if (num_bits == 0) {
        var decoded = try std.array_list.Managed(T).initCapacity(allocator, num_values);
        try decoded.appendNTimes(0, num_values);
        return decoded;
    }

    var decoded = try std.array_list.Managed(T).initCapacity(allocator, num_values);
    errdefer decoded.deinit();

    var pos: usize = 0;
    while (decoded.items.len < num_values and pos < buf.len) {
        const vi = varint.decodeVarint(buf[pos..]);
        pos += vi.bytes;

        if (vi.result & 1 == 1) {
            // Bit-packed run: (vi.result >> 1) groups of 8 values each.
            // Each group occupies exactly num_bits bytes (8 values × num_bits bits / 8).
            const num_groups = vi.result >> 1;
            const run_values = num_groups * 8;
            const run_bytes = num_groups * num_bits;
            const take = @min(run_values, num_values - decoded.items.len);
            const old_len = decoded.items.len;
            try decoded.resize(old_len + take);
            try bitpack.bitpackDecodeInto(buf[pos .. pos + run_bytes], num_bits, take, T, decoded.items[old_len..]);
            pos += run_bytes;
        } else {
            // RLE run: (vi.result >> 1) repeated copies of a ceil(num_bits/8)-byte value.
            const run_length = vi.result >> 1;
            const val_bytes = (@as(usize, num_bits) + 7) / 8;
            var v_buf: [@sizeOf(T)]u8 = [_]u8{0} ** @sizeOf(T);
            @memcpy(v_buf[0..val_bytes], buf[pos .. pos + val_bytes]);
            pos += val_bytes;
            const v = std.mem.readInt(T, &v_buf, .little);
            const take = @min(run_length, num_values - decoded.items.len);
            try decoded.appendNTimes(v, take);
        }
    }

    return decoded;
}

pub fn rleBitmapDecode(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !std.array_list.Managed(u64) {
    // Read varint to determine if we are bitpacking or rle
    const vi = varint.decodeVarint(buf);
    const size = (num_values + 63) / 64;
    if (vi.result & 1 == 1) {
        // bitpacking
        var decoded = try std.array_list.Managed(u64).initCapacity(allocator, size);
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
        var decoded = try std.array_list.Managed(u64).initCapacity(allocator, size);

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
