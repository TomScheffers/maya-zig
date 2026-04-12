const std = @import("std");
pub const DataType = @import("datatype.zig").DataType;
pub const Bitmap = @import("bitmap.zig").Bitmap;
pub const LargeString: type = @import("../utils/string.zig").LargeString;
pub const array_map = @import("array_map.zig");

pub fn ArrayType(comptime T: type) type {
    return struct {
        data: std.array_list.Managed(T),
        const data_type = T;
        const Self = @This();

        pub fn init(data: []T, allocator: std.mem.Allocator) Self {
            const tmp = std.array_list.Managed(data_type).fromOwnedSlice(allocator, data);
            return Self{ .data = tmp };
        }

        pub fn initEmpty(allocator: std.mem.Allocator) Self {
            const tmp = std.array_list.Managed(data_type).init(allocator);
            return Self{ .data = tmp };
        }

        pub fn initCapacity(capacity: usize, allocator: std.mem.Allocator) !Self {
            const tmp = try std.array_list.Managed(data_type).initCapacity(allocator, capacity);
            return Self{ .data = tmp };
        }

        pub fn fromArrayList(data: std.array_list.Managed(T)) Self {
            return Self{ .data = data };
        }

        fn deinit(self: Self) void {
            switch (data_type) {
                LargeString => {
                    for (self.data.items) |s| {
                        s.deinit(self.data.allocator);
                    }
                },
                else => {},
            }
            self.data.deinit();
        }

        fn len(self: Self) usize {
            return self.data.items.len;
        }

        fn extend(self: *Self, other: *Self) !void {
            try self.*.data.appendSlice(other.data.items);
            other.deinit();
        }

        fn fmtIdx(self: Self, buf: *[24]u8, index: usize) ![]const u8 {
            if (index > self.len()) return "";
            const value = self.data.items[index];
            switch (data_type) {
                bool => {
                    return std.fmt.bufPrint(buf, "{any}", .{value});
                },
                u8, u16, u32, u64, i8, i16, i32, i64 => {
                    return std.fmt.bufPrint(buf, "{d}", .{value});
                },
                f32, f64 => {
                    return std.fmt.bufPrint(buf, "{d:.2}", .{value});
                },
                LargeString => {
                    buf.* = value.fmt(24);
                    return buf[0..@min(value.length, 24)];
                },
                else => {
                    return "";
                },
            }
        }
    };
}

pub const Array = union(DataType) {
    Boolean: ArrayType(bool),
    UInt8: ArrayType(u8),
    UInt16: ArrayType(u16),
    UInt32: ArrayType(u32),
    UInt64: ArrayType(u64),
    Int8: ArrayType(i8),
    Int16: ArrayType(i16),
    Int32: ArrayType(i32),
    Int64: ArrayType(i64),
    Float32: ArrayType(f32),
    Float64: ArrayType(f64),
    Binary: ArrayType(LargeString),
    Date: ArrayType(u32),

    const Self = Array;

    pub fn fromArrayList(comptime T: type, data: std.array_list.Managed(T)) Self {
        return switch (T) {
            bool => Self{ .Boolean = ArrayType(T).fromArrayList(data) },
            u8 => Self{ .UInt8 = ArrayType(T).fromArrayList(data) },
            u16 => Self{ .UInt16 = ArrayType(T).fromArrayList(data) },
            u32 => Self{ .UInt32 = ArrayType(T).fromArrayList(data) },
            u64 => Self{ .UInt64 = ArrayType(T).fromArrayList(data) },
            i8 => Self{ .Int8 = ArrayType(T).fromArrayList(data) },
            i16 => Self{ .Int16 = ArrayType(T).fromArrayList(data) },
            i32 => Self{ .Int32 = ArrayType(T).fromArrayList(data) },
            i64 => Self{ .Int64 = ArrayType(T).fromArrayList(data) },
            f32 => Self{ .Float32 = ArrayType(T).fromArrayList(data) },
            f64 => Self{ .Float64 = ArrayType(T).fromArrayList(data) },
            LargeString => Self{ .Binary = ArrayType(T).fromArrayList(data) },
            else => unreachable,
        };
    }

    pub fn deinit(self: Self) void {
        switch (self) {
            inline else => |x| x.deinit(),
        }
    }

    pub fn len(self: Self) usize {
        switch (self) {
            inline else => |x| return x.len(),
        }
    }

    pub fn fmtIdx(self: Self, buf: *[24]u8, index: usize) ![]const u8 {
        switch (self) {
            inline else => |x| return x.fmtIdx(buf, index),
        }
    }

    pub fn extend(self: *Self, other: *Self) !void {
        if (@as(DataType, self.*) != @as(DataType, other.*)) return error.NotSameType;

        switch (@as(DataType, self.*)) {
            inline else => |x| {
                var arr1 = @field(self, @tagName(x));
                var arr2 = @field(other, @tagName(x));
                try arr1.extend(&arr2);
                @field(self, @tagName(x)) = arr1;
            },
        }
    }
};

pub const Series: type = struct {
    name: []const u8,
    data_type: DataType,
    data: Array,
    dictionary: ?Array,
    validity: ?Bitmap,
    allocator: std.mem.Allocator,
    const Self = Series;

    pub fn init(name: ?[]const u8, data_type: DataType, data: Array, dictionary: ?Array, validity: ?Bitmap, allocator: std.mem.Allocator) !Self {
        const sn = if (name) |nm| try allocator.dupe(u8, nm) else "Unknown";
        return Self{ .name = sn, .data_type = data_type, .data = data, .dictionary = dictionary, .validity = validity, .allocator = allocator };
    }

    pub fn deinit(self: Self) void {
        self.data.deinit();
        if (self.dictionary) |d| {
            d.deinit();
        }
        if (self.validity) |v| {
            v.deinit();
        }
    }

    pub fn len(self: Self) usize {
        return self.data.len();
    }

    pub fn withName(self: *Self, name: []const u8) void {
        self.*.name = name;
    }

    pub fn withValidity(self: *Self, validity: Bitmap) void {
        self.*.validity = validity;
    }

    pub fn withDictionary(self: *Self, dictionary: Array) void {
        self.*.dictionary = dictionary;
    }

    pub fn unmapDictionary(self: *Self) !void {
        if (self.dictionary) |dic| {
            switch (dic) {
                inline else => |x| {
                    const T = @TypeOf(x).data_type;
                    const indices = self.data.UInt32.data.items;
                    const dict_items = x.data.items;
                    const result = try self.allocator.alloc(T, indices.len);
                    for (indices, 0..) |idx, i| {
                        result[i] = dict_items[idx];
                    }
                    self.data = Array.fromArrayList(T, std.array_list.Managed(T).fromOwnedSlice(self.allocator, result));
                    self.dictionary = null;
                },
            }
        }
    }

    pub fn fmtIdx(self: Self, buf: *[24]u8, index: usize) ![]const u8 {
        if (self.dictionary) |d| {
            switch (self.data) {
                .UInt32 => |x| {
                    const didx: usize = @intCast(x.data.items[index]);
                    return d.fmtIdx(buf, didx);
                },
                .UInt64 => |x| {
                    const didx: usize = @intCast(x.data.items[index]);
                    return d.fmtIdx(buf, didx);
                },
                else => unreachable,
            }
        } else {
            return self.data.fmtIdx(buf, index);
        }
    }

    pub fn extend(self: *Self, other: *Self) !void {
        try self.data.extend(&other.data);
        if (self.validity) |*sv| {
            if (other.validity) |*ov| {
                try sv.extend(ov);
            }
        }
    }
};
