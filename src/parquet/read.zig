const std = @import("std");
const expect = std.testing.expect;
const md = @import("metadata.zig");
const page = @import("page.zig");

const hlp = @import("../utils/helpers.zig");
const series = @import("../core/series.zig");
const frame = @import("../core/frame.zig");
const Chunk = frame.Chunk;

const Frame = frame.Frame;

const PAR1 = [4]u8{ 'P', 'A', 'R', '1' };

pub fn readParquetData(buf: []u8, metadata: md.MetaData, allocator: std.mem.Allocator) !Frame {
    var chunks = std.ArrayList(Chunk).init(allocator);
    for (metadata.row_groups.items) |rg| {
        var columns = std.ArrayList(series.Series).init(allocator);
        for (rg.columns.items) |cc| {
            const column = try page.readColumnChunk(buf, cc, metadata, allocator);
            try columns.append(column);
        }
        try chunks.append(Chunk{ .columns = columns });
    }
    return Frame{ .chunks = chunks };
}

pub fn readParquet(path: []const u8, allocator: std.mem.Allocator) !Frame {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_buffer = try file.readToEndAlloc(allocator, 100_000_000);
    const fl = file_buffer.len;
    defer allocator.free(file_buffer);

    // Check PAR1 tags
    try expect(std.mem.eql(u8, file_buffer[0..4], &PAR1));
    try expect(std.mem.eql(u8, file_buffer[(fl - 4)..], &PAR1));

    // Read metadata
    // https://github.com/apache/parquet-format/blob/master/src/main/thrift/parquet.thrift#L1163
    // https://parquet.apache.org/docs/file-format/metadata/

    const metadata_bytes: u64 = hlp.sliceToInt(file_buffer[(fl - 8)..(fl - 4)]);
    const metadata = try md.parseMetadata(file_buffer[(fl - metadata_bytes - 8)..(fl - 8)], allocator);
    defer metadata.deinit();

    // Read data
    const df = try readParquetData(file_buffer, metadata, allocator);
    return df;
}
