const std = @import("std");
const helpers = @import("../../utils/helpers.zig");

fn shiftAmountType(comptime T: type) type {
    const bits = @bitSizeOf(T);
    return if (bits <= 8) u3 else if (bits <= 16) u4 else if (bits <= 32) u5 else if (bits <= 64) u6 else unreachable;
}

fn decodePack(comptime T: type, input: []u8, output: []T, num_bits: usize, num_values: usize) !void {
    // Packs are 8 * num_bits long, such that we have full byte ranges
    if (num_bits == 0) {
        @memset(output, 0);
    } else {
        const msk: T = if (T == u1) 1 else std.math.pow(T, 2, @intCast(num_bits)) - 1;
        const num_bits_c: shiftAmountType(T) = @intCast(num_bits);
        const bytes: comptime_int = @sizeOf(T);
        const bits: comptime_int = @bitSizeOf(T);
        var v = try helpers.sliceToUInt(input[0..bytes], T); // Read first 8 bytes as u64
        for (0..num_values) |i| {
            const start_bit = (i * num_bits);
            if ((start_bit % bits) + num_bits > bits) { // We will overflow number of bits in v, so reset v
                const start_byte = start_bit / 8;
                const end_byte = start_byte + bytes;
                v = try helpers.sliceToUInt(input[start_byte..end_byte], T);
                v = (v >> @intCast(start_bit - start_byte * 8));
            }
            output[i] = @intCast(v & msk);
            v = (v >> num_bits_c);
        }
    }
}

pub fn bitpackDecode(buf: []u8, num_bits: usize, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    if (num_bits * num_values / 8 > buf.len) return error.BufferTooSmall;
    var result = try allocator.alloc(T, num_values);
    const chunk_size: usize = @bitSizeOf(T);
    for (0..num_values / chunk_size) |c| {
        const start_byte = c * chunk_size * num_bits / 8;
        try decodePack(T, buf[start_byte..], result[c * chunk_size .. (c + 1) * chunk_size], num_bits, chunk_size);
    }
    // Here we deal with the values left because of the chunk_size
    const values_left = num_values % chunk_size;
    if (values_left > 0) {
        const start_value = (num_values - values_left);
        const start_byte = start_value * num_bits / 8;
        var input_residual = try allocator.alloc(u8, chunk_size * num_bits / 8);
        defer allocator.free(input_residual);
        @memcpy(input_residual[0..buf[start_byte..].len], buf[start_byte..]);
        var output_residual: [chunk_size]T = undefined;
        try decodePack(T, input_residual[0..], output_residual[0..], num_bits, chunk_size);
        @memcpy(result[start_value..], output_residual[0..values_left]);
    }
    return std.array_list.Managed(T).fromOwnedSlice(allocator, result[0..]);
}

pub fn bitpackDecodeSIMD(buf: []u8, num_bits: u5, num_values: usize, comptime T: type, allocator: std.mem.Allocator) !std.array_list.Managed(T) {
    if (@sizeOf(T) > 8) return error.TooManyBytes;
    if (num_bits * num_values / 8 > buf.len) return error.BufferTooSmall;
    const lanes: comptime_int = 512 / @bitSizeOf(T); // Number of lanes in a 512-bit SIMD register (for u64)

    if (@as(usize, @intCast(num_bits)) * lanes + 7 < @bitSizeOf(T)) {
        var result = try allocator.alloc(T, num_values);
        const msk: T = if (T == u1) 1 else std.math.pow(T, 2, @intCast(num_bits)) - 1;

        // We can fit num_bits * lanes + 8 within one T, makes it an easy to splat single u
        var shifts: [lanes]shiftAmountType(T) = undefined;
        inline for (0..lanes) |l| {
            shifts[l] = @intCast(l * num_bits);
        }
        const vshifts: @Vector(lanes, shiftAmountType(T)) = shifts;

        var i: usize = 0;
        while (i + lanes <= num_values) {
            const byte_offset = (i * num_bits) / 8;
            const bit_offset = (i * num_bits) % 8;

            const chunk = try helpers.sliceToUInt(buf[byte_offset..@min(buf.len, byte_offset + @sizeOf(T))], T) >> @intCast(bit_offset);

            const vchunk: @Vector(lanes, T) = @splat(chunk);
            const vshifted = vchunk >> vshifts;
            const vmasked = vshifted & @as(@Vector(lanes, T), @splat(msk));

            @memcpy(result[i..][0..lanes], @as([lanes]T, vmasked)[0..]);
            i += lanes;
        }
        if (i < num_values) {
            const byte_offset = (i * num_bits) / 8;
            try decodePack(T, buf[byte_offset..], result[i..num_values], num_bits, num_values - i);
        }
        return std.array_list.Managed(T).fromOwnedSlice(allocator, result[0..]);
    } else {
        return bitpackDecode(buf, num_bits, num_values, T, allocator);
    }
}
