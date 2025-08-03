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

// Structure to hold file handle and metadata for efficient reading
pub const ParquetReader = struct {
    file: std.fs.File,
    metadata: md.MetaData,
    allocator: std.mem.Allocator,

    pub fn init(path: []const u8, allocator: std.mem.Allocator) !ParquetReader {
        var file = try std.fs.cwd().openFile(path, .{});

        // Get file size
        const file_size = try file.getEndPos();

        // Read footer to check PAR1 magic and get metadata size
        try file.seekTo(file_size - 8);
        var footer_buf: [8]u8 = undefined;
        _ = try file.readAll(&footer_buf);

        // Check PAR1 magic at end
        try expect(std.mem.eql(u8, footer_buf[4..8], &PAR1));

        // Get metadata size
        const metadata_bytes: u64 = hlp.sliceToInt(footer_buf[0..4]);

        // Read metadata
        const metadata_start = file_size - metadata_bytes - 8;
        try file.seekTo(metadata_start);
        const metadata_buf = try allocator.alloc(u8, metadata_bytes);
        defer allocator.free(metadata_buf);
        _ = try file.readAll(metadata_buf);

        const metadata = try md.parseMetadata(metadata_buf, allocator);

        // Check PAR1 magic at beginning
        try file.seekTo(0);
        var header_buf: [4]u8 = undefined;
        _ = try file.readAll(&header_buf);
        try expect(std.mem.eql(u8, &header_buf, &PAR1));

        return ParquetReader{
            .file = file,
            .metadata = metadata,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParquetReader) void {
        self.metadata.deinit();
        self.file.close();
    }

    // Read specific column chunk by seeking to its position
    fn readColumnChunkFromFile(self: *ParquetReader, column_chunk: md.ColumnChunk, metadata: md.MetaData) !series.Series {
        const offset: u64 = @intCast(column_chunk.meta_data.?.data_page_offset);
        const size: u64 = @intCast(column_chunk.meta_data.?.total_compressed_size);

        // Debug: Print column info
        const column_name = column_chunk.meta_data.?.path_in_schema.items[0];

        // Get file size to validate offset
        const file_size = try self.file.getEndPos();
        if (offset + size > file_size) {
            std.debug.print("ERROR: Column data extends beyond file. File size: {d}, requested: {d}-{d}\n", .{ file_size, offset, offset + size });
            return error.InvalidOffset;
        }

        // Let's check what's at this file position - read first few bytes for comparison
        if (std.mem.eql(u8, column_name, "txt")) {
            std.debug.print("NEW APPROACH: Reading column '{s}': buf[{d}..{d}] (offset={d}, size={d})\n", .{ column_name, offset, offset + size, offset, size });
            try self.file.seekTo(offset);
            var debug_header: [16]u8 = undefined;
            const debug_bytes_read = try self.file.read(&debug_header);
            std.debug.print("First {d} bytes at offset {d}: ", .{ debug_bytes_read, offset });
            for (debug_header[0..debug_bytes_read]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }

        // Seek back and read the full column data
        try self.file.seekTo(offset);
        const column_data = try self.allocator.alloc(u8, size);
        defer self.allocator.free(column_data);

        const bytes_read = try self.file.readAll(column_data);
        if (bytes_read != size) {
            std.debug.print("ERROR: Expected {d} bytes, but read {d} bytes at offset {d}\n", .{ size, bytes_read, offset });
            return error.IncompleteRead;
        }

        // Calculate sum AFTER reading the data
        var sum: u64 = 0;
        for (column_data) |byte| {
            sum += byte;
        }

        if (std.mem.eql(u8, column_name, "txt")) {
            std.debug.print("NEW APPROACH: Allocated {d} bytes, read {d} bytes, sum: {d}\n", .{ size, bytes_read, sum });
        }

        return try page.readColumnChunk(column_data, column_chunk, metadata, self.allocator);
    }

    // Read specific columns from a row group
    pub fn readRowGroupSelective(self: *ParquetReader, row_group_idx: usize, column_names: ?[]const []const u8) !Chunk {
        if (row_group_idx >= self.metadata.row_groups.items.len) {
            return error.RowGroupIndexOutOfBounds;
        }

        const row_group = self.metadata.row_groups.items[row_group_idx];
        var selected_columns = std.ArrayList(series.Series).init(self.allocator);

        // If no column names specified, read all columns
        if (column_names == null) {
            for (row_group.columns.items) |column_chunk| {
                const column = try self.readColumnChunkFromFile(column_chunk, self.metadata);
                try selected_columns.append(column);
            }
        } else {
            // Read only specified columns
            for (column_names.?) |col_name| {
                for (row_group.columns.items) |column_chunk| {
                    const schema_name = column_chunk.meta_data.?.path_in_schema.items[0];
                    if (std.mem.eql(u8, schema_name, col_name)) {
                        const column = try self.readColumnChunkFromFile(column_chunk, self.metadata);
                        try selected_columns.append(column);
                        break;
                    }
                }
            }
        }

        return Chunk{ .columns = selected_columns };
    }

    // Read specific columns from all row groups
    pub fn readAllRowGroupsSelective(self: *ParquetReader, column_names: ?[]const []const u8) !Frame {
        var chunks = std.ArrayList(Chunk).init(self.allocator);

        for (0..self.metadata.row_groups.items.len) |i| {
            const chunk = try self.readRowGroupSelective(i, column_names);
            try chunks.append(chunk);
        }

        return Frame{ .chunks = chunks };
    }

    // Get list of available column names
    pub fn getColumnNames(self: *ParquetReader) !std.ArrayList([]u8) {
        var names = std.ArrayList([]u8).init(self.allocator);

        if (self.metadata.row_groups.items.len > 0) {
            const first_row_group = self.metadata.row_groups.items[0];
            for (first_row_group.columns.items) |column_chunk| {
                const schema_name = column_chunk.meta_data.?.path_in_schema.items[0];
                const owned_name = try self.allocator.dupe(u8, schema_name);
                try names.append(owned_name);
            }
        }

        return names;
    }
};

// Convenience function: Read specific columns using the new optimized API
pub fn readParquetSelective(path: []const u8, column_names: ?[]const []const u8, allocator: std.mem.Allocator) !Frame {
    var reader = try ParquetReader.init(path, allocator);
    defer reader.deinit();

    return try reader.readAllRowGroupsSelective(column_names);
}

// Convenience function: Get column names from a parquet file
pub fn getParquetColumns(path: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]u8) {
    var reader = try ParquetReader.init(path, allocator);
    defer reader.deinit();

    return try reader.getColumnNames();
}

// Main readParquet function - uses optimized ParquetReader approach
pub fn readParquet(path: []const u8, allocator: std.mem.Allocator) !Frame {
    var reader = try ParquetReader.init(path, allocator);
    defer reader.deinit();

    // Read all columns from all row groups (but still more efficient than loading entire file)
    return try reader.readAllRowGroupsSelective(null);
}

// OLD FUNCTIONS

// Original functions restored for compatibility
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

        // DEBUG: Compare with new approach
        const column_name = column_chunk.meta_data.?.path_in_schema.items[0];

        // Show first few bytes of the slice we're about to pass
        if ((std.mem.eql(u8, column_name, "txt")) and (s1 + 16 <= buf.len)) {
            std.debug.print("\nOLD APPROACH: Reading column '{s}': buf[{d}..{d}] (offset={d}, size={d})\n", .{ column_name, s1, s1 + sz, s1, sz });
            var sum: u64 = 0;
            for (buf[s1 .. s1 + sz]) |byte| {
                sum += byte;
            }
            std.debug.print("OLD APPROACH: Sum of buffer bytes: {d}\n", .{sum});
            std.debug.print("OLD APPROACH: First 16 bytes of buf[{d}..{d}]: ", .{ s1, s1 + 16 });
            for (buf[s1 .. s1 + @min(16, sz)]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }

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

// Original readParquet function that loads entire file into memory
pub fn readParquetOld(path: []const u8, allocator: std.mem.Allocator) !Frame {
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
