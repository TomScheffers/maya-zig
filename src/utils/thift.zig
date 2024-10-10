const std = @import("std");
const expect = std.testing.expect;
const varint = @import("varint.zig");
const helpers = @import("helpers.zig");
const Allocator = std.mem.Allocator;

// https://simonkjohnston.life/thrift-specs/protocol-compact.html
// Thift: https://github.com/apache/thrift/blob/master/doc/specs/thrift-compact-protocol.md

const TValueTag = enum { BOOL, I8, I16, I32, I64, DOUBLE, BINARY, LIST, SET, MAP, STRUCT, UUID, NULL };

pub const TValue: type = union(TValueTag) {
    BOOL: bool,
    I8: i8,
    I16: i16,
    I32: i32,
    I64: i64,
    DOUBLE: f64,
    BINARY: []u8,
    LIST: std.ArrayList(TValue),
    SET: std.ArrayList(TValue),
    MAP: struct { keys: std.ArrayList(TValue), values: std.ArrayList(TValue) },
    STRUCT: struct { offsets: std.ArrayList(u32), values: std.ArrayList(TValue) },
    UUID: []u8,
    NULL: void,

    pub fn deinit(self: TValue) void {
        switch (self) {
            .LIST, .SET => |x| x.deinit(),
            .MAP => |x| {
                x.keys.deinit();
                x.values.deinit();
            },
            .STRUCT => |x| {
                x.offsets.deinit();
                x.values.deinit();
            },
            else => {},
        }
    }

    fn fromFieldType(ft: u4) TValue {
        switch (ft) {}
    }

    fn fancy(node: *const TValue) void {
        switch (node.*) {
            .BOOL => |x| {
                std.debug.print("BOOLEAN: {any}", .{x});
            },
            .I8 => |x| {
                std.debug.print("I8: {d}", .{x});
            },
            .I16 => |x| {
                std.debug.print("I16: {d}", .{x});
            },
            .I32 => |x| {
                std.debug.print("I32: {d}", .{x});
            },
            .I64 => |x| {
                std.debug.print("I64: {d}", .{x});
            },
            .DOUBLE => |x| {
                std.debug.print("DOUBLE: {}", .{x});
            },
            .BINARY => |x| {
                std.debug.print("BINARY: {s}", .{x});
            },
            .LIST, .SET => {
                std.debug.print("LIST", .{});
            },
            .MAP => {
                std.debug.print("MAP", .{});
            },
            .STRUCT => {
                std.debug.print("STRUCT", .{});
            },
            .UUID => {
                std.debug.print("UUID", .{});
            },
            .NULL => {
                std.debug.print("NULL", .{});
            },
        }
    }
};

pub fn print_tree(node: *const TValue, depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) std.debug.print(" ", .{});
    TValue.fancy(node);
    std.debug.print("\n", .{});
    switch (node.*) {
        .LIST, .SET => |x| {
            for (x.items) |v| {
                print_tree(&v, depth + 1);
            }
        },
        .MAP => |x| {
            for (x.values.items) |v| {
                print_tree(&v, depth + 1);
            }
        },
        .STRUCT => |x| {
            var j: u8 = 0;
            while (j < x.values.items.len) : (j += 1) {
                std.debug.print("FI {}", .{x.offsets.items[j]});
                print_tree(&x.values.items[j], depth + 1);
            }
        },
        else => {},
    }
}

pub fn procceedNode(data: []u8, offset: *usize, field_type: u4, allocator: Allocator) !TValue {
    if (data.len < offset.*) {
        return TValue{ .NULL = undefined };
    }

    switch (field_type) {
        1 => {
            return TValue{ .BOOL = true };
        },
        2 => {
            return TValue{ .BOOL = false };
        },
        3 => {
            const r = varint.decodeZigzagVarint(data[(offset.*)..]);
            offset.* += r.bytes;
            return TValue{ .I8 = @intCast(r.result) };
        },
        4 => {
            const r = varint.decodeZigzagVarint(data[(offset.*)..]);
            offset.* += r.bytes;
            return TValue{ .I16 = @intCast(r.result) };
        },
        5 => {
            const r = varint.decodeZigzagVarint(data[(offset.*)..]);
            offset.* += r.bytes;
            return TValue{ .I32 = @intCast(r.result) };
        },
        6 => {
            const r = varint.decodeZigzagVarint(data[(offset.*)..]);
            offset.* += r.bytes;
            return TValue{ .I64 = @intCast(r.result) };
        },
        7 => {
            const d: u64 = helpers.sliceToInt(data[(offset.*)..(offset.* + 8)]);
            offset.* += 8;
            return TValue{ .DOUBLE = @floatFromInt(d) };
        },
        8 => {
            const r = varint.decodeVarint(data[(offset.*)..]);
            offset.* += r.bytes;
            const bytes = data[(offset.*)..(offset.* + r.result)];
            offset.* += r.result;
            return TValue{ .BINARY = bytes };
        },
        9, 10 => {
            var list = std.ArrayList(TValue).init(allocator);
            const ds8 = helpers.splitU8(data[(offset.*)]);
            if (ds8.left == 0xF) {
                offset.* += 1;
                const r = varint.decodeVarint(data[(offset.*)..]);
                const size = r.result;
                offset.* += r.bytes;

                var s: usize = 0;
                while (s < size) : (s += 1) {
                    const c = try procceedNode(data, offset, ds8.right, allocator);
                    try list.append(c);
                }
            } else {
                const size = ds8.left;
                offset.* += 1;

                var s: usize = 0;
                while (s < size) : (s += 1) {
                    const c = try procceedNode(data, offset, ds8.right, allocator);
                    try list.append(c);
                }
            }

            const node = TValue{ .LIST = list };
            return node;
        },
        11 => {
            var keys = std.ArrayList(TValue).init(allocator);
            var values = std.ArrayList(TValue).init(allocator);

            if (data[offset.*] == 0) {
                offset.* += 1;
                return TValue{ .MAP = .{ .keys = keys, .values = values } };
            }

            // Read size
            const r = varint.decodeVarint(data[(offset.*)..]);
            const size = r.result;
            offset.* += r.bytes;

            // Read types
            const ds8 = helpers.splitU8(data[(offset.*)]);
            offset.* += 1;

            var s: usize = 0;
            while (s < size) : (s += 1) {
                const k = try procceedNode(data, offset, ds8.left, allocator);
                const v = try procceedNode(data, offset, ds8.right, allocator);
                try keys.append(k);
                try values.append(v);
            }
            return TValue{ .MAP = .{ .keys = keys, .values = values } };
        },
        12 => {
            var offsets = std.ArrayList(u32).init(allocator);
            var values = std.ArrayList(TValue).init(allocator);

            var field_id: u32 = 0;
            while ((data[(offset.*)] != 0) and (data.len > offset.*)) { // STRUCT ENDS WITH 00000000 byte
                const ds8 = helpers.splitU8(data[(offset.*)]);
                if (ds8.left == 0) {
                    field_id += data[(offset.*) + 1];
                    offset.* += 2;
                    const c = try procceedNode(data, offset, ds8.right, allocator);
                    try offsets.append(field_id);
                    try values.append(c);
                } else {
                    field_id += ds8.left;
                    offset.* += 1;
                    const c = try procceedNode(data, offset, ds8.right, allocator);
                    try offsets.append(field_id);
                    try values.append(c);
                }
            }
            offset.* += 1; // Else we are stuck at the termination byte
            return TValue{ .STRUCT = .{ .offsets = offsets, .values = values } };
        },
        13 => {
            const uuid: []u8 = data[(offset.*)..(offset.* + 16)];
            offset.* += 16;
            return TValue{ .UUID = uuid };
        },
        else => {
            //std.debug.print("Please implement number {}\n", .{field_type});
            return TValue{ .NULL = undefined };
        },
    }
}

test "bool" {
    const allocator = std.heap.page_allocator;
    var x = [1]u8{0x01};
    var offset: usize = 0;
    const node1 = try procceedNode(x[0..], &offset, 1, allocator);
    try expect(node1.BOOL == true);
    try expect(offset == 0);

    const node2 = try procceedNode(x[0..], &offset, 2, allocator);
    try expect(node2.BOOL == false);
    try expect(offset == 0);
}

test "integer" {
    const allocator = std.heap.page_allocator;
    var x = [1]u8{0x01};
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 3, allocator);
    try expect(node.I8 == -1);
    try expect(offset == 1);
}

test "i32" {
    const allocator = std.heap.page_allocator;
    var x = [4]u8{
        0b10000001,
        0b10000001,
        0b10000001,
        0b00000001,
    };
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 5, allocator);
    try expect(node.I32 == -1056833);
    try expect(offset == 4);
}

test "double" {
    const allocator = std.heap.page_allocator;
    var x = [8]u8{ 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01 };
    var offset: usize = 0;
    _ = try procceedNode(x[0..], &offset, 7, allocator);
    try expect(offset == 8);
}

test "binary" {
    const allocator = std.heap.page_allocator;
    var x = [10]u8{ 0x9, 'H', 'e', 'l', 'l', 'o', ' ', 'Z', 'i', 'g' };
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 8, allocator);
    std.debug.print("Binary {s}\n", .{node.BINARY});
    try expect(offset == 10);
}

test "list" { //
    const allocator = std.heap.page_allocator;
    var x = [3]u8{ 0b00100011, 0x01, 0x02 };
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 9, allocator);
    try expect(node.LIST.items[0].I8 == -1);
    try expect(node.LIST.items[1].I8 == 1);
    try expect(offset == 3);
}

test "long list" { //
    const allocator = std.heap.page_allocator;
    var x = [4]u8{ 0b11110011, 0x2, 0x1, 0x2 }; // 1111 for long list, 0011 for type int, 0x2 for length 2 and 2 ints
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 9, allocator);
    try expect(node.LIST.items[0].I8 == -1);
    try expect(node.LIST.items[1].I8 == 1);
    try expect(offset == 4);
}

test "empty map" { //
    const allocator = std.heap.page_allocator;
    var x = [1]u8{0x0};
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 11, allocator);
    try expect(node.MAP.keys.items.len == 0);
    try expect(offset == 1);
}

test "map" { //
    const allocator = std.heap.page_allocator;
    var x = [6]u8{ 0x02, 0b00110011, 0x09, 0xA, 0xB, 0xC }; // size of 2, key/value types int8
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 11, allocator);
    try expect(node.MAP.keys.items.len == 2);
    try expect(node.MAP.values.items.len == 2);
    try expect(offset == 6);
}

test "struct" { //
    const allocator = std.heap.page_allocator;
    var x = [5]u8{ 0b00010011, 0x01, 0b00010011, 0x02, 0x0 };
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 12, allocator);
    try expect(node.STRUCT.offsets.items.len == 2);
    try expect(node.STRUCT.values.items.len == 2);
    try expect(offset == 5);
}

test "long struct" { //
    const allocator = std.heap.page_allocator;
    var x = [7]u8{ 0b00000011, 0x01, 0x01, 0b00000011, 0x01, 0x01, 0x0 };
    var offset: usize = 0;
    const node = try procceedNode(x[0..], &offset, 12, allocator);
    try expect(node.STRUCT.offsets.items.len == 2);
    try expect(node.STRUCT.values.items.len == 2);
    try expect(offset == 7);
}
