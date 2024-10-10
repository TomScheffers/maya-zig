pub const std = @import("std");
pub const LargeString: type = @import("../utils/string.zig").LargeString;
pub const md: type = @import("../parquet/metadata.zig");

pub const DataTypeFamily = enum { Boolean, UInt, Int, Float, Binary, Date };

pub const DataType: type = enum {
    Boolean,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Int8,
    Int16,
    Int32,
    Int64,
    Float32,
    Float64,
    // Decimal,
    // String,
    Binary,
    // BinaryOffset,
    Date,
    // Datetime,
    // Duration,
    // Time,
    // Array,
    // List,
    // Null,
    // Categorical,
    // Enum,
    // Struct,
    // Unknown,

    pub fn getFamily(self: DataType) DataTypeFamily {
        return switch (self) {
            .Boolean => DataTypeFamily.Boolean,
            .UInt8, .UInt16, .UInt32, .UInt64 => DataTypeFamily.UInt,
            .Int8, .Int16, .Int32, .Int64 => DataTypeFamily.Int,
            .Float32, .Float64 => DataTypeFamily.Float,
            .Binary => DataTypeFamily.Binary,
            .Date => DataTypeFamily.Date,
        };
    }

    pub fn getByteSize(self: DataType) u8 {
        return switch (self) {
            .Boolean, .UInt8, .Int8 => 1,
            .UInt16, .Int16 => 2,
            .UInt32, .Int32, .Float32 => 4,
            .UInt64, .Int64, .Float64 => 8,
            .Binary => 255,
            .Date => 4,
        };
    }

    pub fn isSuperType(a: DataType, b: DataType) !bool {
        if (a == b) return true;
        if (a.getFamily() == b.getFamily()) {
            if (a.getByteSize() > b.getByteSize()) {
                return true;
            } else {
                return false;
            }
        } else {
            return error.IncompatibleTypes;
        }
    }

    pub fn isCompatible(a: DataType, b: DataType) bool {
        return (a.getFamily() == b.getFamily());
    }

    pub fn getZigType(self: DataType) type {
        return switch (self) {
            .Boolean => bool,
            .UInt8 => u8,
            .UInt16 => u16,
            .UInt32 => u32,
            .UInt64 => u64,
            .Int8 => i8,
            .Int16 => i16,
            .Int32 => i32,
            .Int64 => i64,
            .Float32 => f32,
            .Float64 => f64,
            .Binary => LargeString,
            .Date => u32,
        };
    }

    pub fn getDataType(comptime T: type) DataType {
        return switch (T) {
            bool => DataType.Boolean,
            u8 => DataType.UInt8,
            u16 => DataType.UInt16,
            u32 => DataType.UInt32,
            u64 => DataType.UInt64,
            i8 => DataType.Int8,
            i16 => DataType.Int16,
            i32 => DataType.Int32,
            i64 => DataType.Int64,
            f32 => DataType.Float32,
            f64 => DataType.Float64,
            LargeString => DataType.Binary,
            else => unreachable,
        };
    }

    pub fn fromSchemaElement(schema: md.SchemaElement) DataType {
        if (schema.converted_type) |ct| {
            return switch (ct) {
                .UTF8 => DataType.Binary,
                .UINT_8 => DataType.UInt8,
                .UINT_16 => DataType.UInt16,
                .UINT_32 => DataType.UInt32,
                .UINT_64 => DataType.UInt64,
                .INT_8 => DataType.Int8,
                .INT_16 => DataType.Int16,
                .INT_32 => DataType.Int32,
                .INT_64 => DataType.Int64,
                .DATE => DataType.Date,
                // MAP,
                // MAP_KEY_VALUE,
                // LIST,
                // ENUM,
                // DECIMAL,
                // TIME_MILLIS,
                // TIME_MICROS,
                // TIMESTAMP_MILLIS,
                // TIMESTAMP_MICROS,
                // .JSON,
                // .BSON,
                // .INTERVAL,
                else => unreachable,
            };
        } else {
            return switch (schema.binary_type.?) {
                .BOOLEAN => DataType.Boolean,
                .INT32 => DataType.Int32,
                .INT64 => DataType.Int64,
                .INT96 => unreachable,
                .FLOAT => DataType.Float32,
                .DOUBLE => DataType.Float64,
                .BYTE_ARRAY => DataType.Binary,
                .FIXED_LEN_BYTE_ARRAY => DataType.Binary,
            };
        }
    }

    pub fn fmt(self: DataType) []const u8 {
        return switch (self) {
            .Boolean => "bool",
            .UInt8 => "u8",
            .UInt16 => "u16",
            .UInt32 => "u32",
            .UInt64 => "u64",
            .Int8 => "i8",
            .Int16 => "i16",
            .Int32 => "i32",
            .Int64 => "i64",
            .Float32 => "f32",
            .Float64 => "f64",
            .Binary => "str",
            .Date => "date",
        };
    }
};

pub const Any: type = union(DataType) {
    Boolean: bool,
    UInt8: u8,
    UInt16: u16,
    UInt32: u32,
    UInt64: u64,
    Int8: i8,
    Int16: i16,
    Int32: i32,
    Int64: i64,
    Float32: f32,
    Float64: f64,
    Binary: LargeString,
    Date: u32,

    pub fn init(comptime T: type, value: T) Any {
        const dt = comptime DataType.getDataType(T);
        const tag = @tagName(dt);
        return @unionInit(Any, tag, value);
    }

    pub fn eql(self: Any, other: Any) bool {
        switch (@as(DataType, self)) {
            .Binary => {
                return self.Binary.eql(other.Binary);
            },
            inline else => |x| {
                const tag = @tagName(x);
                return (@field(self, tag) == @field(other, tag));
            },
        }
    }
};
