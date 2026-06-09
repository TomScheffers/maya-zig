const std = @import("std");

const ast = @import("../ast/mod.zig");
const json = @import("json.zig");
const expr_transform = @import("expr.zig");

pub const TransformFromError = error{
    OutOfMemory,
} || json.TransformJsonError;

/// `SelectStmt.fromClause` → Maya `FromClause`.
pub fn transformFromClause(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    from_clause: std.json.Value,
) TransformFromError!ast.FromClause {
    const arr = try json.expectArray(from_clause);
    var items = try std.ArrayListUnmanaged(*ast.FromItem).initCapacity(allocator, arr.items.len);
    errdefer items.deinit(allocator);

    for (arr.items) |elem| {
        const item = try transformFromItem(allocator, arena, elem);
        try items.append(allocator, item);
    }

    return .{ .items = try items.toOwnedSlice(allocator) };
}

/// Dispatch `{ "RangeVar": … }`, `{ "JoinExpr": … }`, etc.
pub fn transformFromItem(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    node: std.json.Value,
) TransformFromError!*ast.FromItem {
    const tagged = try json.taggedNode(node);

    const item = try arena.create(ast.FromItem);
    if (std.mem.eql(u8, tagged.tag, "RangeVar")) {
        item.* = .{ .table = try transformRangeVar(allocator, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "JoinExpr")) {
        item.* = .{ .join = try transformJoinExpr(allocator, arena, tagged.fields) };
    } else if (std.mem.eql(u8, tagged.tag, "RangeSubselect")) {
        return error.UnsupportedNode;
    } else {
        return error.UnsupportedNode;
    }

    return item;
}

pub fn transformRangeVar(allocator: std.mem.Allocator, fields: std.json.ObjectMap) TransformFromError!ast.TableRef {
    const relname = json.optionalString(fields, "relname") orelse return error.MissingField;

    var table = ast.TableRef{
        .name = .{ .relation = try allocator.dupe(u8, relname) },
        .inherit = json.getBool(fields, "inh", true),
        .location = json.getI32(fields, "location", -1),
    };

    if (json.optionalString(fields, "catalogname")) |catalog| {
        table.name.catalog = try allocator.dupe(u8, catalog);
    }
    if (json.optionalString(fields, "schemaname")) |schema| {
        table.name.schema = try allocator.dupe(u8, schema);
    }
    if (fields.get("alias")) |alias_value| {
        if (alias_value != .null) {
            table.alias = try transformAlias(allocator, alias_value);
        }
    }

    return table;
}

pub fn transformJoinExpr(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    fields: std.json.ObjectMap,
) TransformFromError!ast.Join {
    const larg = fields.get("larg") orelse return error.MissingField;
    const rarg = fields.get("rarg") orelse return error.MissingField;

    const jointype = json.optionalString(fields, "jointype") orelse return error.MissingField;
    const kind = ast.JoinKind.fromPgTag(jointype) orelse return error.UnsupportedNode;

    var join = ast.Join{
        .kind = kind,
        .natural = json.getBool(fields, "isNatural", false),
        .left = try transformFromItem(allocator, arena, larg),
        .right = try transformFromItem(allocator, arena, rarg),
    };

    if (fields.get("usingClause")) |using_value| {
        if (using_value != .null) {
            join.using_columns = try json.parseStringList(allocator, using_value);
        }
    }

    if (fields.get("quals")) |quals_value| {
        if (quals_value != .null) {
            join.on = try expr_transform.transformExpr(allocator, arena, quals_value);
        }
    }

    if (fields.get("alias")) |alias_value| {
        if (alias_value != .null) {
            join.alias = try transformAlias(allocator, alias_value);
        }
    }

    return join;
}

pub fn transformAlias(allocator: std.mem.Allocator, node: std.json.Value) TransformFromError!ast.Alias {
    const tagged = try json.taggedNode(node);
    if (!std.mem.eql(u8, tagged.tag, "Alias")) return error.UnexpectedJson;

    const aliasname = json.optionalString(tagged.fields, "aliasname") orelse return error.MissingField;
    var alias = ast.Alias{
        .name = try allocator.dupe(u8, aliasname),
    };

    if (tagged.fields.get("colnames")) |colnames_value| {
        if (colnames_value != .null) {
            alias.column_names = try json.parseStringList(allocator, colnames_value);
        }
    }

    return alias;
}

test "transform RangeVar with alias" {
    const fixture =
        \\{"RangeVar":{"relname":"orders","inh":true,"relpersistence":"p","alias":{"Alias":{"aliasname":"o"}},"location":14}}
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const table = try transformRangeVar(arena.allocator(), (try json.taggedNode(parsed.value)).fields);

    try std.testing.expectEqualStrings("orders", table.name.relation);
    try std.testing.expect(table.alias != null);
    try std.testing.expectEqualStrings("o", table.alias.?.name);
}

test "transform FROM clause list" {
    const fixture =
        \\[
        \\  {"RangeVar":{"relname":"a","inh":true,"relpersistence":"p","location":1}},
        \\  {"RangeVar":{"relname":"b","inh":true,"relpersistence":"p","location":2}}
        \\]
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const from_clause = try transformFromClause(arena.allocator(), arena.allocator(), parsed.value);

    try std.testing.expectEqual(@as(usize, 2), from_clause.items.len);
    try std.testing.expect(from_clause.items[0].*.table.name.relation.len > 0);
    try std.testing.expectEqualStrings("a", from_clause.items[0].*.table.name.relation);
    try std.testing.expectEqualStrings("b", from_clause.items[1].*.table.name.relation);
}

test "transform nested JoinExpr skeleton" {
    const fixture =
        \\{"JoinExpr":{"jointype":"JOIN_INNER","isNatural":false,"larg":{"RangeVar":{"relname":"orders","inh":true,"relpersistence":"p","location":1}},"rarg":{"RangeVar":{"relname":"items","inh":true,"relpersistence":"p","location":2}},"rtindex":0}}
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const item = try transformFromItem(arena.allocator(), arena.allocator(), parsed.value);
    try std.testing.expectEqual(ast.FromItem.join, std.meta.activeTag(item.*));
    try std.testing.expect(item.join.kind == .inner);
    try std.testing.expectEqualStrings("orders", item.join.left.*.table.name.relation);
    try std.testing.expectEqualStrings("items", item.join.right.*.table.name.relation);
    try std.testing.expect(item.join.on == null);
}
