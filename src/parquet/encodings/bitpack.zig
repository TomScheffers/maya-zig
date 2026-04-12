const std = @import("std");

/// When each packed value is a whole number of little-endian bytes (Parquet common case).
fn decodePackByteAligned(comptime T: type, input: []const u8, output: []T, num_bits: usize, num_values: usize) !void {
    const num_bytes = num_bits / 8;
    const need = try std.math.mul(usize, num_values, num_bytes);
    if (need > input.len) return error.BufferTooSmall;
    var off: usize = 0;
    for (0..num_values) |i| {
        const v: u64 = switch (num_bytes) {
            1 => input[off],
            2 => std.mem.readInt(u16, input[off..][0..2], .little),
            3 => std.mem.readInt(u24, input[off..][0..3], .little),
            4 => std.mem.readInt(u32, input[off..][0..4], .little),
            5 => std.mem.readInt(u40, input[off..][0..5], .little),
            6 => std.mem.readInt(u48, input[off..][0..6], .little),
            7 => std.mem.readInt(u56, input[off..][0..7], .little),
            8 => std.mem.readInt(u64, input[off..][0..8], .little),
            else => unreachable,
        };
        output[i] = @intCast(v);
        off += num_bytes;
    }
}

fn decodePackBitStream(comptime T: type, input: []const u8, output: []T, num_bits: usize, num_values: usize) !void {
    const msk: u64 = (@as(u64, 1) << @intCast(num_bits)) - 1;
    const sh: u6 = @intCast(num_bits);
    var lo: u64 = 0;
    var hi: u64 = 0;
    var avail: usize = 0;
    var in_i: usize = 0;
    for (0..num_values) |i| {
        if (avail < num_bits) {
            if (in_i + 8 <= input.len) {
                const w = std.mem.readInt(u64, input[in_i..][0..8], .little);
                in_i += 8;
                if (avail == 0) {
                    lo = w;
                } else {
                    lo |= w << @intCast(avail);
                    hi = w >> @intCast(64 - avail);
                }
                avail += 64;
            } else {
                while (avail < num_bits) {
                    if (in_i >= input.len) return error.BufferTooSmall;
                    if (avail < 64) {
                        lo |= @as(u64, input[in_i]) << @intCast(avail);
                    } else {
                        hi |= @as(u64, input[in_i]) << @intCast(avail - 64);
                    }
                    in_i += 1;
                    avail += 8;
                }
            }
        }
        output[i] = @intCast(lo & msk);
        if (avail > 64) {
            lo = (lo >> sh) | (hi << @intCast(64 - num_bits));
            hi >>= sh;
        } else {
            lo >>= sh;
        }
        avail -= num_bits;
    }
}

fn decodePack(comptime T: type, input: []const u8, output: []T, num_bits: usize, num_values: usize) !void {
    if (num_bits == 0) {
        @memset(output, 0);
        return;
    }
    if (num_bits > 64) return error.NumBitsTooLarge;
    if (num_bits % 8 == 0) {
        return decodePackByteAligned(T, input, output, num_bits, num_values);
    }
    return decodePackBitStream(T, input, output, num_bits, num_values);
}

/// Decode into a caller-provided buffer. No allocations; `output.len` must be at least `num_values`.
pub fn bitpackDecodeInto(buf: []const u8, num_bits: usize, num_values: usize, comptime T: type, output: []T) !void {
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    const need_bytes = (num_bits * num_values + 7) / 8;
    if (need_bytes > buf.len) return error.BufferTooSmall;
    if (output.len < num_values) return error.OutputTooSmall;
    try decodePack(T, buf, output[0..num_values], num_bits, num_values);
}

/// Decode Parquet bit-packed values (little-endian bit order).
pub fn bitpackDecode(buf: []u8, num_bits: usize, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    const need_bytes = (num_bits * num_values + 7) / 8;
    if (need_bytes > buf.len) return error.BufferTooSmall;
    const result = try allocator.alloc(T, num_values);
    errdefer allocator.free(result);
    try decodePack(T, buf, result, num_bits, num_values);
    return std.array_list.Managed(T).fromOwnedSlice(allocator, result);
}
