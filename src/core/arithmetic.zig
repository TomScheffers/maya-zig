const std = @import("std");
const series = @import("series.zig");
const Series = series.Series;
const DataType = series.DataType;
const LargeString = series.LargeString;

pub fn addValue(comptime T: type, a: anytype, b: anytype) !T {
    switch (T) {
        bool, LargeString => return error.OpNotAllowed,
        else => {
            return a + b;
        },
    }
}

pub fn subtractValue(comptime T: type, a: anytype, b: anytype) !T {
    switch (T) {
        bool, LargeString => return error.OpNotAllowed,
        else => {
            return a - b;
        },
    }
}

pub fn multiplyValue(comptime T: type, a: anytype, b: anytype) !T {
    switch (T) {
        bool, LargeString => return error.OpNotAllowed,
        else => {
            return a * b;
        },
    }
}

pub fn divideValue(comptime T: type, a: anytype, b: anytype) !T {
    switch (T) {
        bool, LargeString => return error.OpNotAllowed,
        else => {
            return a - b;
        },
    }
}

pub fn binaryOp(op: anytype, a: Series, b: Series, allocator: std.mem.Allocator) !Series {
    std.debug.print("\nA: {s}, B: {s}", .{ a.name, b.name });

    if (a.len() != b.len()) return error.NotSameLength;

    switch (@as(DataType, a.data)) {
        inline else => |ta| {
            switch (@as(DataType, b.data)) {
                inline else => |tb| {
                    const cp = comptime DataType.isCompatible(ta, tb);
                    if (!cp) return error.IncompatibleTypes;

                    const a_arr = @field(a.data, @tagName(ta));
                    const b_arr = @field(b.data, @tagName(tb));

                    const st = comptime (ta.getByteSize() > tb.getByteSize());
                    if (st) {
                        var c_arr = try series.ArrayType(ta.getZigType()).initCapacity(a.len(), allocator);
                        for (a_arr.data.items, b_arr.data.items) |e1, e2| {
                            const val = try op(ta.getZigType(), e1, e2);
                            try c_arr.data.append(val);
                        }
                        return Series.init(null, a.data_type, @unionInit(series.Array, @tagName(ta), c_arr), null, null, allocator);
                    } else {
                        var c_arr = try series.ArrayType(tb.getZigType()).initCapacity(a.len(), allocator);
                        for (a_arr.data.items, b_arr.data.items) |e1, e2| {
                            const val = try op(tb.getZigType(), e1, e2);
                            try c_arr.data.append(val);
                        }
                        return Series.init(null, b.data_type, @unionInit(series.Array, @tagName(tb), c_arr), null, null, allocator);
                    }
                },
            }
        },
    }
}

pub fn add(a: Series, b: Series, allocator: std.mem.Allocator) !Series {
    return try binaryOp(addValue, a, b, allocator);
}

pub fn subtract(a: Series, b: Series, allocator: std.mem.Allocator) !Series {
    return try binaryOp(subtractValue, a, b, allocator);
}

pub fn multiply(a: Series, b: Series, allocator: std.mem.Allocator) !Series {
    return try binaryOp(multiplyValue, a, b, allocator);
}

pub fn divide(a: Series, b: Series, allocator: std.mem.Allocator) !Series {
    return try binaryOp(divideValue, a, b, allocator);
}
