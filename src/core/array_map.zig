const std = @import("std");
pub const DataType = @import("datatype.zig").DataType;
pub const Any = @import("datatype.zig").Any;
pub const LargeString: type = @import("../util/string.zig").LargeString;
pub const Array = @import("series.zig").Array;

const AnyHasher = struct {
    pub fn hash(_: AnyHasher, s: Any) u64 {
        var h = std.hash.Wyhash.init(0);
        _ = s;
        return h.final();
    }

    pub fn eql(_: AnyHasher, a: Any, b: Any) bool {
        return a.eql(b);
    }
};

pub const ArrayMapAny: type = struct {
    map: std.HashMap(Any, std.array_list.Managed(usize), AnyHasher, std.hash_map.default_max_load_percentage),
    const Self = @This();

    fn deinit(self: Self) void {
        self.data.deinit();
    }

    pub fn fromArray(array: Array, allocator: std.mem.Allocator) !Self {
        switch (@as(DataType, array)) {
            .Float32, .Float64 => {
                unreachable;
            },
            inline else => |x| {
                const tag = @tagName(x);
                const data_type = comptime x.getZigType();

                // Hash the default type
                var map = std.AutoHashMap(data_type, std.array_list.Managed(usize)).init(allocator);
                defer map.deinit();

                for (@field(array, tag).data.items, 0..) |d, i| {
                    if (map.getPtr(d)) |al| {
                        try al.append(i);
                    } else {
                        var al = std.array_list.Managed(usize).init(allocator);
                        try al.append(i);
                        try map.put(d, al);
                    }
                }

                // Convert keys to Any values
                var any_map = std.HashMap(Any, std.array_list.Managed(usize), AnyHasher, std.hash_map.default_max_load_percentage).init(allocator);
                var iterator = map.iterator();
                while (iterator.next()) |entry| {
                    const key = Any.init(data_type, entry.key_ptr.*);
                    var idxs = try std.array_list.Managed(usize).initCapacity(allocator, entry.value_ptr.*.capacity);
                    try idxs.appendSlice(try entry.value_ptr.*.toOwnedSlice());
                    try any_map.put(key, idxs);
                }

                return Self{ .map = any_map };
            },
        }
    }
};

pub const ArrayMap: type = struct {
    keys: Array,
    indices: std.array_list.Managed(std.array_list.Managed(usize)),
    const Self = @This();

    fn deinit(self: Self) void {
        self.data.deinit();
    }

    pub fn fromArray(array: Array, allocator: std.mem.Allocator) !Self {
        switch (@as(DataType, array)) {
            .Float32, .Float64 => {
                unreachable;
            },
            inline else => |x| {
                const tag = @tagName(x);
                const data_type = comptime x.getZigType();

                // Hash the default type
                var map = std.AutoHashMap(data_type, std.array_list.Managed(usize)).init(allocator);
                defer map.deinit();

                for (@field(array, tag).data.items, 0..) |d, i| {
                    if (map.getPtr(d)) |al| {
                        try al.append(i);
                    } else {
                        var al = std.array_list.Managed(usize).init(allocator);
                        try al.append(i);
                        try map.put(d, al);
                    }
                }

                // Convert keys to Array
                var keys = try std.array_list.Managed(data_type).initCapacity(allocator, map.count());
                var indices = try std.array_list.Managed(std.array_list.Managed(usize)).initCapacity(allocator, map.count());
                var iterator = map.iterator();
                while (iterator.next()) |entry| {
                    try keys.append(entry.key_ptr.*);
                    var idxs = try std.array_list.Managed(usize).initCapacity(allocator, entry.value_ptr.*.items.len);
                    try idxs.appendSlice(try entry.value_ptr.*.toOwnedSlice());
                    try indices.append(idxs);
                }

                return Self{ .keys = Array.fromArrayList(data_type, keys), .indices = indices };
            },
        }
    }
};
