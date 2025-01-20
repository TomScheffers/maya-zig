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

pub fn readColumnChunkWg(buf: []u8, column_chunk: md.ColumnChunk, metadata: md.MetaData, allocator: std.mem.Allocator, result: *series.Series, wg: *std.Thread.WaitGroup) !void {
    wg.start();
    defer wg.finish();
    const column = try page.readColumnChunk(buf, column_chunk, metadata, allocator);
    result.* = column;
}

pub fn readRowGroup(buf: []u8, row_group: md.RowGroup, metadata: md.MetaData, allocator: std.mem.Allocator) !Chunk {
    var wait_group: std.Thread.WaitGroup = .{};
    var thread_handles = try allocator.alloc(std.Thread, row_group.columns.items.len);
    const results = try allocator.alloc(series.Series, row_group.columns.items.len);

    for (row_group.columns.items, 0..) |column_chunk, i| {
        const s1: usize = @intCast(column_chunk.meta_data.?.data_page_offset);
        const sz: usize = @intCast(column_chunk.meta_data.?.total_compressed_size);
        thread_handles[i] = try std.Thread.spawn(
            .{},
            readColumnChunkWg,
            .{ buf[s1 .. s1 + sz], column_chunk, metadata, allocator, &results[i], &wait_group },
        );
    }
    wait_group.wait();
    for (thread_handles) |th| {
        th.join();
    }

    var columns = std.ArrayList(series.Series).init(allocator);
    for (results) |val| {
        try columns.append(val);
    }
    return Chunk{ .columns = columns };
}

pub fn readRowGroupWg(buf: []u8, row_group: md.RowGroup, metadata: md.MetaData, allocator: std.mem.Allocator, result: *Chunk, wg: *std.Thread.WaitGroup) !void {
    wg.start();
    defer wg.finish();
    const column = try readRowGroup(buf, row_group, metadata, allocator);
    result.* = column;
}

pub fn readParquetData(buf: []u8, metadata: md.MetaData, allocator: std.mem.Allocator) !Frame {
    // Make allocator thread safe
    var thread_safe_arena: std.heap.ThreadSafeAllocator = .{
        .child_allocator = allocator,
    };
    const arena = thread_safe_arena.allocator();

    // Threading prep
    var wait_group: std.Thread.WaitGroup = .{};
    var thread_handles = try allocator.alloc(std.Thread, metadata.row_groups.items.len);
    const results = try allocator.alloc(Chunk, metadata.row_groups.items.len);

    // Read row groups into chunks into frame
    for (metadata.row_groups.items, 0..) |row_group, i| {
        thread_handles[i] = try std.Thread.spawn(
            .{},
            readRowGroupWg,
            .{ buf, row_group, metadata, arena, &results[i], &wait_group },
        );
    }
    wait_group.wait();
    for (thread_handles) |th| {
        th.join();
    }

    var chunks = std.ArrayList(Chunk).init(allocator);
    for (results) |val| {
        try chunks.append(val);
    }
    return Frame{ .chunks = chunks };
}

pub fn readParquetDataOld(buf: []u8, metadata: md.MetaData, allocator: std.mem.Allocator) !Frame {
    var chunks = std.ArrayList(Chunk).init(allocator);
    for (metadata.row_groups.items) |rg| {
        var columns = std.ArrayList(series.Series).init(allocator);
        for (rg.columns.items) |column_chunk| {
            const s1: usize = @intCast(column_chunk.meta_data.?.data_page_offset);
            const sz: usize = @intCast(column_chunk.meta_data.?.total_compressed_size);
            const column = try page.readColumnChunk(buf[s1 .. s1 + sz], column_chunk, metadata, allocator);
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
