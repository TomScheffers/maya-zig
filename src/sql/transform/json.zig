const std = @import("std");

pub const TransformJsonError = error{
    UnexpectedJson,
    MissingField,
    UnsupportedNode,
    OutOfMemory,
};

/// A libpg_query node: `{ "RangeVar": { … } }` → tag `"RangeVar"`.
pub const TaggedNode = struct {
    tag: []const u8,
    fields: std.json.ObjectMap,
};

pub fn taggedNode(value: std.json.Value) TransformJsonError!TaggedNode {
    const obj = try expectObject(value);
    if (obj.count() != 1) return error.UnexpectedJson;

    var it = obj.iterator();
    const entry = it.next() orelse return error.UnexpectedJson;

    return .{
        .tag = entry.key_ptr.*,
        .fields = entry.value_ptr.object,
    };
}

pub fn expectObject(value: std.json.Value) TransformJsonError!std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => error.UnexpectedJson,
    };
}

pub fn expectArray(value: std.json.Value) TransformJsonError!std.json.Array {
    return switch (value) {
        .array => |arr| arr,
        else => error.UnexpectedJson,
    };
}

pub fn optionalString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .null => null,
        .string => |s| s,
        else => null,
    };
}

pub fn getBool(obj: std.json.ObjectMap, key: []const u8, default: bool) bool {
    const value = obj.get(key) orelse return default;
    return switch (value) {
        .bool => |b| b,
        else => default,
    };
}

pub fn getI32(obj: std.json.ObjectMap, key: []const u8, default: i32) i32 {
    const value = obj.get(key) orelse return default;
    return switch (value) {
        .integer => |n| @intCast(n),
        else => default,
    };
}

/// Parse `[{"String": {"sval": "col"}}, …]` list nodes from libpg_query.
pub fn parseStringList(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) TransformJsonError![]const []const u8 {
    const arr = try expectArray(value);
    var names = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, arr.items.len);
    errdefer names.deinit(allocator);

    for (arr.items) |elem| {
        const node = try taggedNode(elem);
        if (!std.mem.eql(u8, node.tag, "String")) return error.UnexpectedJson;
        const sval = optionalString(node.fields, "sval") orelse return error.MissingField;
        try names.append(allocator, sval);
    }

    return try names.toOwnedSlice(allocator);
}
