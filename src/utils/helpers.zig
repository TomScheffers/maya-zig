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
