const std = @import("std");

/// Most-significant byte, == 0x80
const MSB: u8 = 0b1000_0000;
/// All bits except for the most significant. Can be used as bitmask to drop the most-signficant
/// bit using `&` (binary-and).
const DROP_MSB: u8 = 0b0111_1111;

fn required_encoded_space_unsigned(v: u64) usize {
    if (v == 0) {
        return 1;
    }

    var logcounter: usize = 0;
    while (v > 0) {
        logcounter += 1;
        v >>= 7;
    }
    return logcounter;
}

fn zigzagToLong(n: i64) i64 {
    return (n >> 1) ^ -(n & 1);
}

pub fn decodeVarint(src: []u8) struct { result: u64, bytes: u8 } {
    var result: u64 = 0;
    var shift: u6 = 0;
    var bytes: u8 = 0;

    for (src) |b| {
        const msb_dropped = b & DROP_MSB;
        result |= (@as(u64, msb_dropped) << shift);
        shift += 7;
        bytes += 1;

        if (b & MSB == 0) {
            break;
        }
    }

    return .{ .result = result, .bytes = bytes };
}

pub fn decodeZigzagVarint(src: []u8) struct { result: i64, bytes: u8 } {
    const varint = decodeVarint(src);
    return .{ .result = zigzagToLong(@intCast(varint.result)), .bytes = varint.bytes };
}
