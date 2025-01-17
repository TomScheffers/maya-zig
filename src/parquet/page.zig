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

pub fn readEncodedData(buf: []u8, encoding: md.Encoding, binary_type: ?md.BinaryType, num_values: usize, allocator: std.mem.Allocator) !Array {
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

pub fn readColumnChunk(buf: []u8, column_chunk: md.ColumnChunk, metadata: md.MetaData, allocator: std.mem.Allocator) !Series {
    const s1: usize = @intCast(column_chunk.meta_data.?.data_page_offset);
    const sz: usize = @intCast(column_chunk.meta_data.?.total_compressed_size);
    const ccb = buf[(s1)..(s1 + sz)];

    // Find binary type for column
    const schema_element: md.SchemaElement = brk: {
        for (metadata.schema.items) |s| {
            if (std.mem.eql(u8, s.name, column_chunk.meta_data.?.path_in_schema.items[0])) {
                break :brk s;
            }
        }
        return error.ColumnNotFound;
    };
    const binary_type = schema_element.binary_type.?;
    // std.debug.print("\n\nCOLUMN CHUNK {s} {any} {any}", .{ column_chunk.meta_data.?.path_in_schema.items[0], binary_type, schema_element.converted_type });

    // Extract page content
    var dictionary: ?Array = null;
    var pages = std.ArrayList(Series).init(allocator);

    var page_offset: usize = 0;
    while (page_offset < sz) {
        // Read page header
        const ph_output = try md.parsePageHeader(ccb[page_offset..], allocator);

        const psz = @as(usize, @intCast(ph_output.page_header.compressed_page_size));
        page_offset += ph_output.header_size;

        // Read page
        const pbuf = ccb[page_offset..(page_offset + psz)];
        const page_header = ph_output.page_header;
        switch (page_header.page_type) {
            md.PageType.DATA_PAGE => {
                const num_value: usize = @intCast(page_header.data_page_header.?.num_values);
                const ucb = try cmp.readZstd(pbuf[0..], allocator);
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

                const page = try readEncodedData(ucb[offset..], page_header.data_page_header.?.encoding, binary_type, num_value, allocator);

                // Set validity of page
                const s = try Series.init(column_chunk.meta_data.?.path_in_schema.items[0], DataType.fromSchemaElement(schema_element), page, null, null, allocator);
                try pages.append(s);
            },
            md.PageType.INDEX_PAGE => {
                unreachable;
            },
            md.PageType.DICTIONARY_PAGE => {
                const ucb = try cmp.readZstd(pbuf[0..], allocator);
                defer allocator.free(ucb);
                const num_value: usize = @intCast(page_header.dictionary_page_header.?.num_value);
                dictionary = try readEncodedData(ucb, page_header.dictionary_page_header.?.encoding, binary_type, num_value, allocator);
            },
            md.PageType.DATA_PAGE_V2 => {
                const num_value: usize = @intCast(page_header.data_page_header_v2.?.num_values);

                // Definition levels https://blog.x.com/engineering/en_us/a/2013/dremel-made-simple-with-parquet
                const dlb: usize = @intCast(page_header.data_page_header_v2.?.definition_levels_byte_length);
                const validity = try readDefinitionLevels(pbuf[0..dlb], num_value, allocator);

                // Repetition levels
                const rlb: usize = @intCast(page_header.data_page_header_v2.?.repetition_levels_byte_length);

                // Compressed data page
                const ucb = try cmp.readZstd(pbuf[(dlb + rlb)..], allocator);
                defer allocator.free(ucb);

                const page = try readEncodedData(ucb, page_header.data_page_header_v2.?.encoding, binary_type, num_value, allocator);

                // Set validity of page
                const s = try Series.init(column_chunk.meta_data.?.path_in_schema.items[0], DataType.fromSchemaElement(schema_element), page, null, validity, allocator);
                try pages.append(s);
            },
        }
        page_offset += psz;
    }

    // Concatenate pages
    var s: Series = pages.items[0];
    var i: usize = 1;
    while (i < pages.items.len) : (i += 1) {
        try s.extend(&pages.items[i]);
    }

    if (s.len() != column_chunk.meta_data.?.num_values) {
        std.debug.print("\nISSUE: Mismatch in size of concatenated page (FILL WITH NULLS?): {}", .{s.len()});
    }

    // Set dictionary if available
    if (dictionary) |dict| {
        s.withDictionary(dict);
    }

    // Map dictionary to values when binary type is smaller then 4 bytes (u32 is used for idxs)
    switch (s.data_type) {
        .Boolean, .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64 => {
            try s.unmapDictionary();
        },
        else => {},
    }

    std.debug.print("\nName of series {s} {}", .{ s.name, s.data_type });

    return s;
}
