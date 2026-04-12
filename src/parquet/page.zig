const std = @import("std");
const md = @import("metadata.zig");
const enc = @import("encodings/mod.zig");
const cmp = @import("compressions.zig");
const LargeString = @import("../utils/string.zig").LargeString;
const series = @import("../core/series.zig");
const Array = series.Array;
const Bitmap = series.Bitmap;
const Series = series.Series;
const DataType = series.DataType;

const time = std.time;
const Instant = time.Instant;

pub fn readEncodedData(buf: []u8, encoding: md.Encoding, binary_type: ?md.BinaryType, num_values: usize, allocator: std.mem.Allocator) !Array {
    // std.debug.print("\nENCODINGS {any}", .{encoding});
    switch (encoding) {
        md.Encoding.PLAIN => {
            switch (binary_type.?) {
                md.BinaryType.BOOLEAN => {
                    unreachable;
                },
                md.BinaryType.INT32 => {
                    const arr = try enc.plain.plainDecodeInt(buf, i32, allocator);
                    return Array.fromArrayList(i32, arr);
                },
                md.BinaryType.INT64 => {
                    const arr = try enc.plain.plainDecodeInt(buf, i64, allocator);
                    return Array.fromArrayList(i64, arr);
                },
                md.BinaryType.INT96 => {
                    unreachable;
                },
                md.BinaryType.FLOAT => {
                    const arr = try enc.plain.plainDecodeFloat(buf, f32, allocator);
                    return Array.fromArrayList(f32, arr);
                },
                md.BinaryType.DOUBLE => {
                    const arr = try enc.plain.plainDecodeFloat(buf, f64, allocator);
                    return Array.fromArrayList(f64, arr);
                },
                md.BinaryType.BYTE_ARRAY => {
                    const arr = try enc.plain.plainDecodeBytes(buf, num_values, allocator);
                    return Array.fromArrayList(LargeString, arr);
                },
                md.BinaryType.FIXED_LEN_BYTE_ARRAY => {
                    const arr = try enc.plain.plainDecodeFixedBytes(buf, num_values, allocator);
                    return Array.fromArrayList(LargeString, arr);
                },
            }
        },
        md.Encoding.RLE => {
            const arr = try enc.rle.rleHybridDecode(buf, 1, num_values, u8, allocator);
            return Array.fromArrayList(u8, arr);
        },
        md.Encoding.RLE_DICTIONARY => {
            // FIRST BYTE CONTAINS SIZE OF ENCODED BITS
            const num_bits: u5 = @intCast(buf[0]);
            const arr = try enc.rle.rleHybridDecode(buf[1..], num_bits, num_values, u32, allocator);
            return Array.fromArrayList(u32, arr);
        },
        else => {
            return error.EncodingNotDefined;
        },
    }
    unreachable;
}

pub fn readDefinitionLevels(buf: []u8, num_values: usize, allocator: std.mem.Allocator) !Bitmap {
    const arr = try enc.rle.rleBitmapDecode(buf, num_values, allocator);
    return Bitmap{ .data = arr, .len = num_values };
}

pub fn readDataPage(buf: []u8, column_chunk: md.ColumnChunk, page_header: md.PageHeader, schema_element: md.SchemaElement, allocator: std.mem.Allocator) !Series {
    const num_value: usize = @intCast(page_header.data_page_header.?.num_values);
    const ucb = try cmp.readZstd(buf[0..], allocator);
    defer allocator.free(ucb);

    // Repetition levels, Definition levels and then Encoded values
    var offset: usize = 0;

    // Repetition levels
    switch (schema_element.repetition_type.?) {
        .REPEATED => {
            const vbuf = @as(*[4]u8, @ptrCast(ucb[0..4].ptr)).*;
            const length = std.mem.readInt(u32, &vbuf, std.builtin.Endian.little);
            _ = try readDefinitionLevels(ucb[4 .. 4 + length], num_value, allocator);
            offset += 4 + length;
        },
        else => {},
    }

    // Definition levels
    var validity: ?Bitmap = null;
    switch (schema_element.repetition_type.?) {
        .OPTIONAL, .REPEATED => {
            const vbuf = @as(*[4]u8, @ptrCast(ucb[0..4].ptr)).*;
            const length = std.mem.readInt(u32, &vbuf, std.builtin.Endian.little);
            validity = try readDefinitionLevels(ucb[offset + 4 .. offset + 4 + length], num_value, allocator);
            offset += 4 + length;
        },
        else => {},
    }

    const page = try readEncodedData(ucb[offset..], page_header.data_page_header.?.encoding, schema_element.binary_type.?, num_value, allocator);

    // Set validity of page
    const s = try Series.init(column_chunk.meta_data.?.path_in_schema.items[0], DataType.fromSchemaElement(schema_element), page, null, null, allocator);
    return s;
}

pub fn readDataPageV2(buf: []u8, column_chunk: md.ColumnChunk, page_header: md.PageHeader, schema_element: md.SchemaElement, allocator: std.mem.Allocator) !Series {
    const num_value: usize = @intCast(page_header.data_page_header_v2.?.num_values);

    // Definition levels https://blog.x.com/engineering/en_us/a/2013/dremel-made-simple-with-parquet
    const dlb: usize = @intCast(page_header.data_page_header_v2.?.definition_levels_byte_length);
    const validity = try readDefinitionLevels(buf[0..dlb], num_value, allocator);

    // Repetition levels
    const rlb: usize = @intCast(page_header.data_page_header_v2.?.repetition_levels_byte_length);

    // Compressed data page
    const ucb = try cmp.readZstd(buf[dlb + rlb ..], allocator);
    defer allocator.free(ucb);

    const page = try readEncodedData(ucb, page_header.data_page_header_v2.?.encoding, schema_element.binary_type, num_value, allocator);

    // Set validity of page
    const s = try Series.init(column_chunk.meta_data.?.path_in_schema.items[0], DataType.fromSchemaElement(schema_element), page, null, validity, allocator);
    return s;
}

pub fn readDictionaryPage(buf: []u8, page_header: md.PageHeader, binary_type: md.BinaryType, allocator: std.mem.Allocator) !Array {
    const ucb = try cmp.readZstd(buf[0..], allocator);
    defer allocator.free(ucb);
    const num_value: usize = @intCast(page_header.dictionary_page_header.?.num_value);
    return try readEncodedData(ucb, page_header.dictionary_page_header.?.encoding, binary_type, num_value, allocator);
}

pub fn readColumnChunk(buf: []u8, column_chunk: md.ColumnChunk, metadata: md.MetaData, allocator: std.mem.Allocator) !Series {
    const start = try Instant.now();

    // Find binary type for column
    const schema_element: md.SchemaElement = brk: {
        for (metadata.schema.items) |s| {
            if (std.mem.eql(u8, s.name, column_chunk.meta_data.?.path_in_schema.items[0])) {
                break :brk s;
            }
        }
        return error.ColumnNotFound;
    };

    // Decode pages sequentially
    var dictionary: ?Array = null;
    var data = std.array_list.Managed(Series).init(allocator);

    var page_offset: usize = 0;
    while (page_offset < buf.len) {
        const ph_output = try md.parsePageHeader(buf[page_offset..], allocator);
        const psz: usize = @intCast(ph_output.page_header.compressed_page_size);
        page_offset += ph_output.header_size;
        const page_buf = buf[page_offset .. page_offset + psz];
        page_offset += psz;

        switch (ph_output.page_header.page_type) {
            .DATA_PAGE => {
                const s = try readDataPage(page_buf, column_chunk, ph_output.page_header, schema_element, allocator);
                if (s.len() > 0) try data.append(s);
            },
            .DATA_PAGE_V2 => {
                const s = try readDataPageV2(page_buf, column_chunk, ph_output.page_header, schema_element, allocator);
                if (s.len() > 0) try data.append(s);
            },
            .DICTIONARY_PAGE => {
                dictionary = try readDictionaryPage(page_buf, ph_output.page_header, schema_element.binary_type.?, allocator);
            },
            .INDEX_PAGE => {},
        }
    }

    // When a dictionary is present, some pages use RLE_DICTIONARY (producing UInt32
    // index arrays) while others may fall back to PLAIN (producing the native type).
    // Resolve dictionary indices per-page so all pages share the same native type
    // before concatenation.
    if (dictionary) |dict| {
        for (data.items) |*d| {
            // Only unmap pages that actually contain dictionary indices (UInt32)
            // AND where the dictionary has entries to look up.
            // PLAIN-encoded fallback pages already carry the native type.
            if (@as(DataType, d.data) == .UInt32 and dict.len() > 0) {
                d.withDictionary(dict);
                try d.unmapDictionary();
            }
        }
    }

    // Concatenate pages
    if (data.items.len == 0) return error.NoDataPages;
    var s: Series = data.items[0];
    for (1..data.items.len) |i| {
        try s.extend(&data.items[i]);
    }

    if (s.len() != column_chunk.meta_data.?.num_values) {
        std.debug.print("\nISSUE: Mismatch in size of concatenated page (FILL WITH NULLS?): {}", .{s.len()});
    }

    const end = try Instant.now();
    const elapsed1: f64 = @floatFromInt(end.since(start));

    if (dictionary) |dict| {
        std.debug.print("\nReading series {s} with {d} pages with dict len {d} took: {d:.3}ms\n", .{ s.name, data.items.len, dict.len(), elapsed1 / time.ns_per_s });
    } else {
        std.debug.print("\nReading series {s} with {d} pages took: {d:.3}ms\n", .{ s.name, data.items.len, elapsed1 / time.ns_per_s });
    }

    return s;
}
