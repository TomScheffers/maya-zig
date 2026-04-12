const std = @import("std");

pub const Bitmap: type = struct {
    data: std.array_list.Managed(u64),
    len: usize,

    pub fn init(allocator: std.mem.Allocator) Bitmap {
        const data = std.array_list.Managed(u64).init(allocator);
        return Bitmap{ .data = data, .len = 0 };
    }

    pub fn initCapacity(capacity: usize, allocator: std.mem.Allocator) !Bitmap {
        const data = try std.array_list.Managed(u64).initCapacity(allocator, capacity);
        return Bitmap{ .data = data, .len = 0 };
    }

    pub fn deinit(self: Bitmap) void {
        self.data.deinit();
    }

    pub fn extend(self: *Bitmap, other: *Bitmap) !void {
        const last_bits_set: u6 = @intCast(self.len % 64);
        self.len += other.len;
        if (last_bits_set == 0) {
            try self.data.appendSlice(try other.data.toOwnedSlice());
        } else {
            // This one hurts because we need to shift all the bits in other by last_bits_set
            const new_bits: u6 = 63 - last_bits_set + 1; // u6 cannot represent 64 :]

            // Packing last part of self: last_bits_set = 10, residual_bits = 54, last u64 = lsb10 of self + lsb54 of other
            const msk_lsbs = ~(~@as(u64, 0) << last_bits_set);
            const msk_lsbo = ~(~@as(u64, 0) << new_bits);
            self.data.items[self.data.items.len - 1] = (self.data.items[self.data.items.len - 1] & msk_lsbs) | ((other.data.items[0] & msk_lsbo) << last_bits_set);

            // Add combined parts of other: last_bits_set = 10, residual_bits = 54, u64 = msb10 of previous >> 54 + lsb54 of other << 10
            const msk_msb = ~msk_lsbo;
            const msk_lsb = msk_lsbo;
            var i: usize = 1;
            while (i < other.data.items.len) : (i += 1) {
                const v = ((other.data.items[i - 1] & msk_msb) >> new_bits) | ((other.data.items[i] & msk_lsb) << last_bits_set);
                try self.data.append(v);
            }

            // Add last msb part of other
            const vl = (other.data.items[other.data.items.len - 1] & msk_msb) >> new_bits;
            try self.data.append(vl);
        }
    }

    pub fn _and(self: Bitmap, other: Bitmap, allocator: std.mem.Allocator) !Bitmap {
        if (self.len != other.len) return error.IncompatibleSizes;
        var b = try Bitmap.initCapacity(self.data.items.len, allocator);
        for (self.data.items, other.data.items) |x, y| {
            try b.data.append(x & y);
        }
        b.len = self.len;
        return b;
    }

    pub fn _not(self: Bitmap, allocator: std.mem.Allocator) !Bitmap {
        var b = try Bitmap.initCapacity(self.data.items.len, allocator);
        for (self.data.items) |x| {
            try b.data.append(~x);
        }
        b.len = self.len;
        return b;
    }

    pub fn countTrue(self: Bitmap) usize {
        var count: usize = 0;
        for (self.data.items) |value| {
            count += @popCount(value);
        }
        return count;
    }

    pub fn countFalse(self: Bitmap) usize {
        return self.len - self.countTrue();
    }
};
