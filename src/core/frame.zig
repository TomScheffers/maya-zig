const std = @import("std");
const DataType = @import("datatype.zig").DataType;
const Any = @import("datatype.zig").Any;
const series = @import("series.zig");
const Series = series.Series;
const ArrayMap = @import("array_map.zig").ArrayMap;
const LargeString: type = @import("../utils/string.zig").LargeString;
const Expr = @import("expr.zig").Expr;

pub const Chunk: type = struct {
    columns: std.ArrayList(Series),

    pub fn deinit(self: Chunk) void {
        for (self.columns) |c| {
            c.deinit();
        }
        self.columns.deinit();
    }

    pub fn get_column_names(self: *Chunk, allocator: std.mem.Allocator) !std.ArrayList(LargeString) {
        var column_names = std.ArrayList(LargeString).initCapacity(allocator, self.columns.items.len);
        for (self.columns) |column| {
            try column_names.append(column.name);
        }
        return column_names;
    }

    pub fn get_column(self: Chunk, name: []const u8) !Series {
        std.debug.print("\nFinding column {s}", .{name});
        for (self.columns.items) |column| {
            if (std.mem.eql(u8, column.name, name)) return column;
        }
        return error.ColumnDoesNotExist;
    }

    pub fn with_column(self: *Chunk, name: []const u8, expr: Expr, allocator: std.mem.Allocator) !void {
        var col = try expr.eval(self.*, allocator);
        col.withName(name);
        try self.columns.append(col);
    }
};

pub const Frame: type = struct {
    chunks: std.ArrayList(Chunk),

    pub fn deinit(self: Frame) void {
        for (self.chunks) |c| {
            c.deinit();
        }
        self.chunks.deinit();
    }

    pub fn with_column(self: *Frame, name: []const u8, expr: Expr, allocator: std.mem.Allocator) !void {
        for (self.chunks.items) |*chunk| {
            try chunk.with_column(name, expr, allocator);
        }
    }

    pub fn group_by(self: Frame, names: std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
        // TODO: Kick out columns which are constants (Dictionary len == 1)

        // 3 types: 0. no columns, 1. single column, 2. multiple dictionaries, 3. multiple
        if (names.items.len == 0) {
            unreachable;
        } else if (names.items.len == 1) {
            const column: Series = try self.chunks.items[0].get_column(names.items[0]);
            const array_map: ArrayMap = try ArrayMap.fromArray(column.data, allocator);
            std.debug.print("\nGroup by values: {any}", .{array_map.keys.Int64.data.items});
        } else {
            // TODO: Implement fast path when all columns are dictionaries
            for (names.items) |name| {
                const column: Series = try self.chunks.items[0].get_column(name);
                const array_map: ArrayMap = try ArrayMap.fromArray(column.data, allocator);
                _ = array_map;

                // We have 2 options here: 1. split frame + map group_by again, 2. make all array maps + combine overlapping values
            }
        }
    }

    pub fn print(self: Frame, allocator: std.mem.Allocator) !void {
        const chunk = self.chunks.items[0];

        // Calculate column widths
        var columnWidths = try std.ArrayList(usize).initCapacity(allocator, chunk.columns.items.len);
        defer columnWidths.deinit();

        for (chunk.columns.items) |column| {
            var maxWidth: usize = @max((column.name).len, column.data_type.fmt().len);
            for (0..10) |rowIndex| {
                const f = try column.fmtIdx(rowIndex);
                maxWidth = @max(maxWidth, f.len);
            }
            try columnWidths.append(maxWidth);
        }

        // Print header
        std.debug.print("\n|-", .{});
        for (columnWidths.items, 0..) |width, colIndex| {
            for (0..width) |_| {
                std.debug.print("-", .{});
            }
            if (colIndex < columnWidths.items.len) {
                std.debug.print("-+-", .{});
            }
        }

        // Print names in first row
        std.debug.print("\n| ", .{});
        for (chunk.columns.items, 0..) |column, colIndex| {
            std.debug.print("{s}", .{column.name});
            for (0..columnWidths.items[colIndex] - (column.name).len) |_| {
                std.debug.print(" ", .{});
            }
            if (colIndex < chunk.columns.items.len) {
                std.debug.print(" | ", .{});
            }
        }

        // Print datatypes in second row
        std.debug.print("\n| ", .{});
        for (chunk.columns.items, 0..) |column, colIndex| {
            std.debug.print("{s}", .{column.data_type.fmt()});
            for (0..columnWidths.items[colIndex] - column.data_type.fmt().len) |_| {
                std.debug.print(" ", .{});
            }
            if (colIndex < chunk.columns.items.len) {
                std.debug.print(" | ", .{});
            }
        }

        // Print seperator
        std.debug.print("\n|-", .{});
        for (columnWidths.items, 0..) |width, colIndex| {
            for (0..width) |_| {
                std.debug.print("-", .{});
            }
            if (colIndex < columnWidths.items.len) {
                std.debug.print("-+-", .{});
            }
        }

        // Print 10 row of table
        for (0..10) |rowIndex| {
            std.debug.print("\n| ", .{});
            for (chunk.columns.items, 0..) |column, colIndex| {
                const f = try column.fmtIdx(rowIndex);
                std.debug.print("{s}", .{f});
                for (0..columnWidths.items[colIndex] - f.len) |_| {
                    std.debug.print(" ", .{});
                }

                if (colIndex < chunk.columns.items.len) {
                    std.debug.print(" | ", .{});
                }
            }
        }

        // Print footer
        std.debug.print("\n|-", .{});
        for (columnWidths.items, 0..) |width, colIndex| {
            for (0..width) |_| {
                std.debug.print("-", .{});
            }
            if (colIndex < columnWidths.items.len) {
                std.debug.print("-+-", .{});
            }
        }
    }
};
