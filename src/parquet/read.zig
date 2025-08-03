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

        // Seek to column position and read data
        try self.file.seekTo(offset);
        const column_data = try self.allocator.alloc(u8, size);
        defer self.allocator.free(column_data);
        _ = try self.file.readAll(column_data);

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

// Backward compatible function - now optimized to only read metadata once
pub fn readParquet(path: []const u8, allocator: std.mem.Allocator) !Frame {
    return try readParquetSelective(path, null, allocator);
}
