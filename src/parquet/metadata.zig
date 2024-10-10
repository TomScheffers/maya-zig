const std = @import("std");
const thift = @import("../utils/thift.zig");

const Allocator = std.mem.Allocator;

pub const BinaryType = enum {
    BOOLEAN, //0
    INT32, //1
    INT64, //2
    INT96, //3 deprecated, only used by legacy implementations.
    FLOAT, //4
    DOUBLE, //5
    BYTE_ARRAY, //6
    FIXED_LEN_BYTE_ARRAY, //7
};

fn BinaryTypeFromInt(type_int: i32) BinaryType {
    return switch (type_int) {
        0 => BinaryType.BOOLEAN,
        1 => BinaryType.INT32,
        2 => BinaryType.INT64,
        3 => BinaryType.INT96,
        4 => BinaryType.FLOAT,
        5 => BinaryType.DOUBLE,
        6 => BinaryType.BYTE_ARRAY,
        7 => BinaryType.FIXED_LEN_BYTE_ARRAY,
        else => unreachable,
    };
}

const FieldRepetitionType = enum {
    REQUIRED, // This field is required (can not be null) and each row has exactly 1 value
    OPTIONAL, // The field is optional (can be null) and each row has 0 or 1 values. */
    REPEATED, // The field is repeated and can contain 0 or more values */
};

fn FieldRepetitionTypeFromInt(frt_int: i32) FieldRepetitionType {
    return switch (frt_int) {
        0 => FieldRepetitionType.REQUIRED,
        1 => FieldRepetitionType.OPTIONAL,
        2 => FieldRepetitionType.REPEATED,
        else => unreachable,
    };
}

pub const ConvertedType = enum {
    UTF8,
    MAP,
    MAP_KEY_VALUE,
    LIST,
    ENUM,
    DECIMAL,
    DATE,
    TIME_MILLIS,
    TIME_MICROS,
    TIMESTAMP_MILLIS,
    TIMESTAMP_MICROS,
    UINT_8,
    UINT_16,
    UINT_32,
    UINT_64,
    INT_8,
    INT_16,
    INT_32,
    INT_64,
    JSON,
    BSON,
    INTERVAL,
};

fn CovertedTypeTypeFromInt(ct_int: i32) ?ConvertedType {
    return switch (ct_int) {
        0 => ConvertedType.UTF8,
        1 => ConvertedType.MAP,
        2 => ConvertedType.MAP_KEY_VALUE,
        3 => ConvertedType.LIST,
        4 => ConvertedType.ENUM,
        5 => ConvertedType.DECIMAL,
        6 => ConvertedType.DATE,
        7 => ConvertedType.TIME_MILLIS,
        8 => ConvertedType.TIME_MICROS,
        9 => ConvertedType.TIMESTAMP_MILLIS,
        10 => ConvertedType.TIMESTAMP_MICROS,
        11 => ConvertedType.UINT_8,
        12 => ConvertedType.UINT_16,
        13 => ConvertedType.UINT_32,
        14 => ConvertedType.UINT_64,
        15 => ConvertedType.INT_8,
        16 => ConvertedType.INT_16,
        17 => ConvertedType.INT_32,
        18 => ConvertedType.INT_64,
        19 => ConvertedType.JSON,
        20 => ConvertedType.BSON,
        21 => ConvertedType.INTERVAL,
        else => null,
    };
}

pub const LogicalType = enum {
    STRING, // use ConvertedType UTF8
    MAP, // use ConvertedType MAP
    LIST, // use ConvertedType LIST
    ENUM, // use ConvertedType ENUM
    DECIMAL, // use ConvertedType DECIMAL + SchemaElement.{scale, precision}
    DATE, // use ConvertedType DATE
    TIME,
    TIMESTAMP,
    INTERVAL,
    INTEGER, // use ConvertedType INT_* or UINT_*
    NULL, // no compatible ConvertedType
    JSON, // use ConvertedType JSON
    BSON, // use ConvertedType BSON
    UUID, // no compatible ConvertedType
    FLOAT16, // no compatible ConvertedType
};

fn LogicalTypeFromInt(lt_int: i32) ?LogicalType {
    return switch (lt_int) {
        0 => LogicalType.STRING,
        1 => LogicalType.MAP,
        2 => LogicalType.LIST,
        3 => LogicalType.ENUM,
        4 => LogicalType.DECIMAL,
        5 => LogicalType.DATE,
        6 => LogicalType.TIME,
        7 => LogicalType.TIMESTAMP,
        8 => LogicalType.INTERVAL,
        9 => LogicalType.INTEGER,
        10 => LogicalType.NULL,
        11 => LogicalType.JSON,
        12 => LogicalType.BSON,
        13 => LogicalType.UUID,
        14 => LogicalType.FLOAT16,
        else => null,
    };
}

pub const SchemaElement: type = struct {
    binary_type: ?BinaryType, // Type how data is stored
    type_length: ?i32,
    repetition_type: ?FieldRepetitionType,
    name: []u8,
    num_children: ?i32,
    converted_type: ?ConvertedType,
    scale: ?i32,
    precision: ?i32,
    field_id: ?i32,
    logical_type: ?LogicalType,
};

fn parseSchema(data: thift.TValue, allocator: Allocator) !std.ArrayList(SchemaElement) {
    var schema = std.ArrayList(SchemaElement).init(allocator);
    for (data.LIST.items) |s| {
        var schema_element = SchemaElement{
            .binary_type = null,
            .type_length = null,
            .repetition_type = null,
            .name = "",
            .num_children = null,
            .converted_type = null,
            .scale = null,
            .precision = null,
            .field_id = null,
            .logical_type = null,
        };

        var i: usize = 0;
        while (i < s.STRUCT.offsets.items.len) : (i += 1) {
            switch (s.STRUCT.offsets.items[i]) {
                1 => {
                    schema_element.binary_type = BinaryTypeFromInt(s.STRUCT.values.items[i].I32);
                },
                2 => {
                    schema_element.type_length = s.STRUCT.values.items[i].I32;
                },
                3 => {
                    schema_element.repetition_type = FieldRepetitionTypeFromInt(s.STRUCT.values.items[i].I32);
                },
                4 => {
                    schema_element.name = s.STRUCT.values.items[i].BINARY;
                },
                5 => {
                    schema_element.num_children = s.STRUCT.values.items[i].I32;
                },
                6 => {
                    schema_element.converted_type = CovertedTypeTypeFromInt(s.STRUCT.values.items[i].I32);
                },

                10 => {
                    if (s.STRUCT.values.items[i] == thift.TValue.I32) {
                        schema_element.logical_type = LogicalTypeFromInt(s.STRUCT.values.items[i].I32);
                    }
                },
                else => {},
            }
        }
        try schema.append(schema_element);
    }
    return schema;
}

pub const KeyValue: type = struct {
    key: []u8,
    value: []u8,
};

pub const Encoding: type = enum { PLAIN, PLAIN_DICTIONARY, RLE, BIT_PACKED, DELTA_BINARY_PACKED, DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY, RLE_DICTIONARY, BYTE_STREAM_SPLIT };

fn EncodingFromInt(e_int: i32) ?Encoding {
    return switch (e_int) {
        0 => Encoding.PLAIN,
        2 => Encoding.PLAIN_DICTIONARY,
        3 => Encoding.RLE,
        4 => Encoding.BIT_PACKED,
        5 => Encoding.DELTA_BINARY_PACKED,
        6 => Encoding.DELTA_LENGTH_BYTE_ARRAY,
        7 => Encoding.DELTA_BYTE_ARRAY,
        8 => Encoding.RLE_DICTIONARY,
        9 => Encoding.BYTE_STREAM_SPLIT,
        else => null,
    };
}

pub const CompressionCodec: type = enum {
    UNCOMPRESSED,
    SNAPPY,
    GZIP,
    LZO,
    BROTLI, // Added in 2.4
    LZ4, // DEPRECATED (Added in 2.4)
    ZSTD, // Added in 2.4
    LZ4_RAW, // Added in 2.9
};

fn CompressionCodecFromInt(cc_int: i32) ?CompressionCodec {
    return switch (cc_int) {
        0 => CompressionCodec.UNCOMPRESSED,
        1 => CompressionCodec.SNAPPY,
        2 => CompressionCodec.GZIP,
        3 => CompressionCodec.LZO,
        4 => CompressionCodec.BROTLI,
        5 => CompressionCodec.LZ4,
        6 => CompressionCodec.ZSTD,
        7 => CompressionCodec.LZ4_RAW,
        else => null,
    };
}

pub const PageType: type = enum {
    DATA_PAGE,
    INDEX_PAGE,
    DICTIONARY_PAGE,
    DATA_PAGE_V2,
};

fn PageTypeFromInt(pt_int: i32) ?PageType {
    return switch (pt_int) {
        0 => PageType.DATA_PAGE,
        1 => PageType.INDEX_PAGE,
        2 => PageType.DICTIONARY_PAGE,
        3 => PageType.DATA_PAGE_V2,
        else => null,
    };
}

pub const PageEncodingStats: type = struct {
    page_type: PageType,
    encoding: Encoding,
    count: i32,
};

fn parsePageEncodingStats(data: thift.TValue) !PageEncodingStats {
    return PageEncodingStats{
        .page_type = PageTypeFromInt(getStructAtOffset(data, 1).?.I32).?,
        .encoding = EncodingFromInt(getStructAtOffset(data, 2).?.I32).?,
        .count = getStructAtOffset(data, 3).?.I32,
    };
}

pub const ColumnMetaData: type = struct {
    binary_type: BinaryType,
    encodings: std.ArrayList(Encoding),
    path_in_schema: std.ArrayList([]u8),
    codec: CompressionCodec,
    num_values: i64,
    total_uncompressed_size: i64,
    total_compressed_size: i64,
    key_value_metadata: ?std.ArrayList(KeyValue),
    data_page_offset: i64,
    index_page_offset: ?i64,
    dictionary_page_offset: ?i64,
    statistics: ?void, //TODO IMPLEMENT
    encoding_stats: std.ArrayList(PageEncodingStats),
    bloom_filter_offset: ?i64,
    bloom_filter_length: ?i32,
    size_statistics: ?void, // TODO IMPLEMENT
};

fn parseColumnMetaData(data: thift.TValue, allocator: Allocator) !ColumnMetaData {
    var encodings = std.ArrayList(Encoding).init(allocator);
    for (getStructAtOffset(data, 2).?.LIST.items) |e| {
        try encodings.append(EncodingFromInt(e.I32).?);
    }

    var path_in_schema = std.ArrayList([]u8).init(allocator);
    for (getStructAtOffset(data, 3).?.LIST.items) |e| {
        try path_in_schema.append(e.BINARY);
    }

    var encoding_stats = std.ArrayList(PageEncodingStats).init(allocator);
    if (getStructAtOffset(data, 13)) |n| {
        for (n.LIST.items) |e| {
            try encoding_stats.append(try parsePageEncodingStats(e));
        }
    }

    const column_meta_data = ColumnMetaData{
        .binary_type = BinaryTypeFromInt(getStructAtOffset(data, 1).?.I32),
        .encodings = encodings,
        .path_in_schema = path_in_schema,
        .codec = CompressionCodecFromInt(getStructAtOffset(data, 4).?.I32).?,
        .num_values = getStructAtOffset(data, 5).?.I64,
        .total_uncompressed_size = getStructAtOffset(data, 6).?.I64,
        .total_compressed_size = getStructAtOffset(data, 7).?.I64,
        .key_value_metadata = null,
        .data_page_offset = getStructAtOffset(data, 9).?.I64,
        .index_page_offset = null,
        .dictionary_page_offset = blk: {
            if (getStructAtOffset(data, 11)) |c| {
                break :blk c.I64;
            } else {
                break :blk null;
            }
        },
        .statistics = null,
        .encoding_stats = encoding_stats,
        .bloom_filter_offset = null,
        .bloom_filter_length = null,
        .size_statistics = null, // TODO IMPLEMENT
    };
    return column_meta_data;
}

pub const ColumnChunk: type = struct {
    file_path: ?[]u8,
    file_offset: i64,
    meta_data: ?ColumnMetaData,
    offset_index_offset: ?i64,
    offset_index_length: ?i32,
    column_index_offset: ?i64,
    column_index_length: ?i32,
    crypto_metadata: ?void, // TODO IMPLEMENT
    encrypted_column_metadata: ?[]u8,
};

fn parseColumnChunks(data: thift.TValue, allocator: Allocator) !std.ArrayList(ColumnChunk) {
    var column_chunks = std.ArrayList(ColumnChunk).init(allocator);
    for (data.LIST.items) |node| {
        const ch = ColumnChunk{
            .file_path = null,
            .file_offset = getStructAtOffset(node, 2).?.I64,
            .meta_data = try parseColumnMetaData(getStructAtOffset(node, 3).?, allocator),
            .offset_index_offset = null,
            .offset_index_length = null,
            .column_index_offset = null,
            .column_index_length = null,
            .crypto_metadata = null,
            .encrypted_column_metadata = null,
        };
        try column_chunks.append(ch);
    }
    return column_chunks;
}

const RowGroup: type = struct {
    columns: std.ArrayList(ColumnChunk),
    total_byte_size: i64,
    num_rows: i64,
    sorting_columns: ?void, // TODO IMPLEMENT
    file_offset: i64,
    total_compressed_size: i64,
    ordinal: i16,
};

fn parseRowGroups(data: thift.TValue, allocator: Allocator) !std.ArrayList(RowGroup) {
    var row_groups = std.ArrayList(RowGroup).init(allocator);
    for (data.LIST.items) |node| {
        const rg = RowGroup{
            .columns = try parseColumnChunks(getStructAtOffset(node, 1).?, allocator),
            .total_byte_size = getStructAtOffset(node, 2).?.I64,
            .num_rows = getStructAtOffset(node, 3).?.I64,
            .sorting_columns = null, // TODO IMPLEMENT
            .file_offset = getStructAtOffset(node, 5).?.I64,
            .total_compressed_size = getStructAtOffset(node, 6).?.I64,
            .ordinal = getStructAtOffset(node, 7).?.I16,
        };
        try row_groups.append(rg);
    }
    return row_groups;
}

pub const MetaData: type = struct {
    version: i32,
    schema: std.ArrayList(SchemaElement), // Schema
    num_rows: i64,
    row_groups: std.ArrayList(RowGroup),
    key_value_metadata: ?std.ArrayList(KeyValue),
    created_by: ?[]u8,

    pub fn deinit(self: MetaData) void {
        self.schema.deinit();
        self.row_groups.deinit();
        if (self.key_value_metadata) |kv| {
            kv.deinit();
        }
    }
};

fn getStructAtOffset(node: thift.TValue, offset: usize) ?thift.TValue {
    var s: usize = 0;
    while (s < node.STRUCT.offsets.items.len) : (s += 1) {
        if (node.STRUCT.offsets.items[s] == offset) {
            return node.STRUCT.values.items[s];
        }
    }
    return null;
}

pub fn parseMetadata(data: []u8, allocator: Allocator) !MetaData {
    // Build thift tree from offset=0 with struct as initial type
    var offset: usize = 0;
    const node = try thift.procceedNode(data, &offset, 12, allocator);
    defer node.deinit();

    // Build metadata
    const metadata = MetaData{
        .version = getStructAtOffset(node, 1).?.I32,
        .schema = try parseSchema(getStructAtOffset(node, 2).?, allocator), //B
        .num_rows = getStructAtOffset(node, 3).?.I64,
        .row_groups = try parseRowGroups(getStructAtOffset(node, 4).?, allocator),
        .key_value_metadata = null,
        .created_by = blk: {
            const created_by = getStructAtOffset(node, 6);
            if (created_by) |c| {
                break :blk c.BINARY;
            } else {
                break :blk null;
            }
        },
    };
    return metadata;
}

// Page Header components

pub const DataPageHeader: type = struct {
    num_values: i32,
    encoding: Encoding,
    definition_level_encoding: Encoding,
    repetition_level_encoding: Encoding,
    statistics: ?void,
};

pub fn parseDataPageHeader(node: thift.TValue) DataPageHeader {
    return DataPageHeader{
        .num_values = getStructAtOffset(node, 1).?.I32, //BB
        .encoding = EncodingFromInt(getStructAtOffset(node, 2).?.I32).?,
        .definition_level_encoding = EncodingFromInt(getStructAtOffset(node, 3).?.I32).?,
        .repetition_level_encoding = EncodingFromInt(getStructAtOffset(node, 4).?.I32).?,
        .statistics = null,
    };
}

pub const DictionaryPageHeader: type = struct { num_value: i32, encoding: Encoding, is_sorted: ?bool };

pub fn parseDictionaryPageHeader(node: thift.TValue) DictionaryPageHeader {
    return DictionaryPageHeader{
        .num_value = getStructAtOffset(node, 1).?.I32,
        .encoding = EncodingFromInt(getStructAtOffset(node, 2).?.I32).?,
        .is_sorted = brk: {
            if (getStructAtOffset(node, 3)) |n| {
                break :brk n.BOOL;
            } else {
                break :brk null;
            }
        },
    };
}

pub const DataPageHeaderV2: type = struct { num_values: i32, num_nulls: i32, num_rows: i32, encoding: Encoding, definition_levels_byte_length: i32, repetition_levels_byte_length: i32, is_compressed: ?bool, statistics: ?void };

pub fn parseDataPageHeaderV2(node: thift.TValue) DataPageHeaderV2 {
    return DataPageHeaderV2{ .num_values = getStructAtOffset(node, 1).?.I32, .num_nulls = getStructAtOffset(node, 2).?.I32, .num_rows = getStructAtOffset(node, 3).?.I32, .encoding = EncodingFromInt(getStructAtOffset(node, 4).?.I32).?, .definition_levels_byte_length = getStructAtOffset(node, 5).?.I32, .repetition_levels_byte_length = getStructAtOffset(node, 6).?.I32, .is_compressed = true, .statistics = null };
}

pub const PageHeader: type = struct {
    page_type: PageType,
    uncompressed_page_size: i32,
    compressed_page_size: i32,
    crc: ?i32,
    data_page_header: ?DataPageHeader,
    // index_page_header: ?void,
    dictionary_page_header: ?DictionaryPageHeader,
    data_page_header_v2: ?DataPageHeaderV2,
};

pub fn parsePageHeader(data: []u8, allocator: Allocator) !struct { page_header: PageHeader, header_size: usize } {
    var offset: usize = 0;
    const node = try thift.procceedNode(data, &offset, 12, allocator);
    defer node.deinit();

    const page_header = PageHeader{
        .page_type = PageTypeFromInt(getStructAtOffset(node, 1).?.I32).?,
        .uncompressed_page_size = getStructAtOffset(node, 2).?.I32,
        .compressed_page_size = getStructAtOffset(node, 3).?.I32,
        .crc = brk: {
            if (getStructAtOffset(node, 4)) |c| {
                break :brk c.I32;
            } else {
                break :brk null;
            }
        },
        .data_page_header = brk: {
            if (getStructAtOffset(node, 5)) |c| {
                break :brk parseDataPageHeader(c);
            } else {
                break :brk null;
            }
        },
        .dictionary_page_header = brk: {
            if (getStructAtOffset(node, 7)) |c| {
                break :brk parseDictionaryPageHeader(c);
            } else {
                break :brk null;
            }
        },
        .data_page_header_v2 = brk: {
            if (getStructAtOffset(node, 8)) |c| {
                break :brk parseDataPageHeaderV2(c);
            } else {
                break :brk null;
            }
        },
    };
    return .{ .page_header = page_header, .header_size = offset };
}
