const std = @import("std");

fn decodePack(comptime T: type, input: []const u8, output: []T, num_bits: usize, num_values: usize) !void {
    if (num_bits == 0) {
        @memset(output, 0);
        return;
    }
    if (num_bits > 64) return error.NumBitsTooLarge;
    // Little-endian bit stream: first value occupies bits 0..num_bits-1 of the concatenated byte sequence.
    if (num_bits <= 63) {
        const msk: u64 = (@as(u64, 1) << @intCast(num_bits)) - 1;
        var acc: u64 = 0;
        var avail: usize = 0;
        var in_i: usize = 0;
        for (0..num_values) |out_i| {
            while (avail < num_bits) {
                if (in_i >= input.len) return error.BufferTooSmall;
                acc |= @as(u64, input[in_i]) << @intCast(avail);
                avail += 8;
                in_i += 1;
            }
            output[out_i] = @intCast(acc & msk);
            acc >>= @intCast(num_bits);
            avail -= num_bits;
        }
    } else {
        const msk: u128 = (@as(u128, 1) << @intCast(num_bits)) - 1;
        var acc: u128 = 0;
        var avail: usize = 0;
        var in_i: usize = 0;
        for (0..num_values) |out_i| {
            while (avail < num_bits) {
                if (in_i >= input.len) return error.BufferTooSmall;
                acc |= @as(u128, input[in_i]) << @intCast(avail);
                avail += 8;
                in_i += 1;
            }
            output[out_i] = @intCast(acc & msk);
            acc >>= @intCast(num_bits);
            avail -= num_bits;
        }
    }
}

/// Decode Parquet bit-packed values (little-endian bit order).
pub fn bitpackDecode(buf: []u8, num_bits: usize, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    const need_bytes = (num_bits * num_values + 7) / 8;
    if (need_bytes > buf.len) return error.BufferTooSmall;
    var result = try allocator.alloc(T, num_values);
    const chunk_size: usize = @bitSizeOf(T);
    for (0..num_values / chunk_size) |c| {
        const start_byte = c * chunk_size * num_bits / 8;
        try decodePack(T, buf[start_byte..], result[c * chunk_size .. (c + 1) * chunk_size], num_bits, chunk_size);
    }
    const values_left = num_values % chunk_size;
    if (values_left > 0) {
        const start_value = (num_values - values_left);
        const start_byte = start_value * num_bits / 8;
        var input_residual = try allocator.alloc(u8, (chunk_size * num_bits + 7) / 8);
        defer allocator.free(input_residual);
        @memcpy(input_residual[0..buf[start_byte..].len], buf[start_byte..]);
        var output_residual: [chunk_size]T = undefined;
        try decodePack(T, input_residual[0..], output_residual[0..], num_bits, chunk_size);
        @memcpy(result[start_value..], output_residual[0..values_left]);
    }
    return std.array_list.Managed(T).fromOwnedSlice(allocator, result[0..]);
}
