const std = @import("std");
const dt = @import("datatype.zig");
const DataType = dt.DataType;
const Any = dt.Any;
const series = @import("series.zig");
const Series = series.Series;
const am = @import("arithmetic.zig");
const Chunk = @import("frame.zig").Chunk;

const ExprErrors = error{
    ColumnDoesNotExist,
    OutOfMemory,
    NotSameLength,
    OpNotAllowed,
    IncompatibleTypes,
};

pub const ColumnExpr: type = struct {
    name: []const u8,

    pub fn eval(self: ColumnExpr, chunk: Chunk, allocator: std.mem.Allocator) ExprErrors!Series {
        _ = allocator;
        return chunk.get_column(self.name);
    }
};

pub const LiteralExpr: type = struct {
    value: Any,

    pub fn eval(self: LiteralExpr, chunk: Chunk, allocator: std.mem.Allocator) ExprErrors!Series {
        switch (self.value) {
            inline else => |v| {
                const T = comptime @TypeOf(v);
                var arr = try std.array_list.Managed(T).initCapacity(allocator, chunk.columns.items.len);
                try arr.appendNTimes(v, chunk.columns.items[0].len());
                const s = try Series.init(null, DataType.getDataType(T), series.Array.fromArrayList(T, arr), null, null, allocator);
                return s;
            },
        }
    }
};

pub const UnaryExpr: type = struct {
    value: Any,
};

pub const BinaryOp: type = enum { Add, Subtract, Multiply, Divide };

pub const BinaryExpr: type = struct {
    left: *const Expr,
    op: BinaryOp,
    right: *const Expr,

    pub fn eval(self: BinaryExpr, chunk: Chunk, allocator: std.mem.Allocator) ExprErrors!Series {
        const left = try self.left.eval(chunk, allocator);
        const right = try self.right.eval(chunk, allocator);
        const s: Series = switch (self.op) {
            .Add => try am.add(left, right, allocator),
            .Subtract => try am.subtract(left, right, allocator),
            .Multiply => try am.multiply(left, right, allocator),
            .Divide => try am.divide(left, right, allocator),
        };
        return s;
    }
};

pub const ExprTypes: type = enum {
    Column,
    Literal,
    Binary,
};

pub const Expr: type = union(ExprTypes) {
    Column: ColumnExpr,
    Literal: LiteralExpr,
    Binary: BinaryExpr,

    pub fn lit(comptime T: type, value: T) Expr {
        return Expr{ .Literal = LiteralExpr{ .value = Any.init(T, value) } };
    }

    pub fn column(name: []const u8) Expr {
        return Expr{ .Column = ColumnExpr{ .name = name } };
    }

    pub fn add(self: *const Expr, other: *const Expr) Expr {
        return Expr{ .Binary = BinaryExpr{ .left = self, .op = BinaryOp.Add, .right = other } };
    }

    pub fn eval(self: Expr, chunk: Chunk, allocator: std.mem.Allocator) ExprErrors!Series {
        switch (self) {
            inline else => |x| return x.eval(chunk, allocator),
        }
    }
};
