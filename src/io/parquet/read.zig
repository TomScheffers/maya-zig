const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;
const md = @import("metadata.zig");
const page = @import("page.zig");

const hlp = @import("../../util/helpers.zig");
const ThreadSafeAllocator = @import("../../util/thread_safe_allocator.zig").ThreadSafeAllocator;
const series = @import("../../core/series.zig");
const frame = @import("../../core/frame.zig");
const Chunk = frame.Chunk;
const Frame = frame.Frame;

const PAR1 = [4]u8{ 'P', 'A', 'R', '1' };

const DecodeResult = struct {
    series: ?series.Series,
    err: bool,
};

fn decodeColumnTask(buf: []u8, column_chunk: md.ColumnChunk, metadata: md.MetaData, alloc: std.mem.Allocator, result: *DecodeResult) void {
    result.series = page.readColumnChunk(buf, column_chunk, metadata, alloc) catch {
        result.err = true;
        return;
    };
}

pub const ParquetReader = struct {
    file_data: []u8,
    metadata: md.MetaData,
    allocator: std.mem.Allocator,
    ts_allocator: ThreadSafeAllocator,

    pub fn init(io: std.Io, path: []const u8, allocator: std.mem.Allocator) !ParquetReader {
        const file_data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
        const file_size = file_data.len;

        // Validate PAR1 magic at start and end
        if (!std.mem.eql(u8, file_data[0..4], &PAR1)) return error.InvalidParquetMagic;
        if (!std.mem.eql(u8, file_data[file_size - 4 ..], &PAR1)) return error.InvalidParquetMagic;

        const metadata_bytes: u64 = hlp.sliceToInt(file_data[file_size - 8 .. file_size - 4]);
        const metadata_start = file_size - metadata_bytes - 8;
        const metadata = try md.parseMetadata(file_data[metadata_start .. file_size - 8], allocator);

        return ParquetReader{
            .file_data = file_data,
            .metadata = metadata,
            .allocator = allocator,
            .ts_allocator = .{ .backing = allocator },
        };
    }

    pub fn deinit(self: *ParquetReader) void {
        self.metadata.deinit();
        self.allocator.free(self.file_data);
    }

    fn columnChunkSlice(self: *ParquetReader, column_chunk: md.ColumnChunk) ![]u8 {
        const offset: usize = if (column_chunk.meta_data.?.dictionary_page_offset) |dict_off|
            @intCast(dict_off)
        else
            @intCast(column_chunk.meta_data.?.data_page_offset);
        const size: usize = @intCast(column_chunk.meta_data.?.total_compressed_size);

        if (offset + size > self.file_data.len) return error.InvalidOffset;
        return self.file_data[offset .. offset + size];
    }

    fn collectColumnChunks(self: *ParquetReader, row_group: md.RowGroup, column_names: ?[]const []const u8) !struct { chunks: []md.ColumnChunk, bufs: [][]u8 } {
        var list = std.array_list.Managed(md.ColumnChunk).init(self.allocator);
        if (column_names == null) {
            try list.appendSlice(row_group.columns.items);
        } else {
            for (column_names.?) |col_name| {
                for (row_group.columns.items) |cc| {
                    if (std.mem.eql(u8, cc.meta_data.?.path_in_schema.items[0], col_name)) {
                        try list.append(cc);
                        break;
                    }
                }
            }
        }
        const chunks = try list.toOwnedSlice();
        const bufs = try self.allocator.alloc([]u8, chunks.len);
        for (chunks, 0..) |cc, i| {
            bufs[i] = try self.columnChunkSlice(cc);
        }
        return .{ .chunks = chunks, .bufs = bufs };
    }

    pub fn readAllRowGroupsSelective(self: *ParquetReader, io: std.Io, column_names: ?[]const []const u8) !Frame {
        const num_rg = self.metadata.row_groups.items.len;

        // Collect all column chunks across all row groups into a flat batch
        const rg_infos = try self.allocator.alloc(struct { chunks: []md.ColumnChunk, bufs: [][]u8, start: usize, count: usize }, num_rg);
        defer self.allocator.free(rg_infos);

        var total_columns: usize = 0;
        for (self.metadata.row_groups.items, 0..) |rg, i| {
            const info = try self.collectColumnChunks(rg, column_names);
            rg_infos[i] = .{ .chunks = info.chunks, .bufs = info.bufs, .start = total_columns, .count = info.chunks.len };
            total_columns += info.chunks.len;
        }
        defer for (rg_infos) |info| {
            self.allocator.free(info.chunks);
            self.allocator.free(info.bufs);
        };

        // Flat arrays for all tasks
        const all_bufs = try self.allocator.alloc([]u8, total_columns);
        defer self.allocator.free(all_bufs);
        const all_chunks = try self.allocator.alloc(md.ColumnChunk, total_columns);
        defer self.allocator.free(all_chunks);
        const results = try self.allocator.alloc(DecodeResult, total_columns);
        defer self.allocator.free(results);
        @memset(results, .{ .series = null, .err = false });

        for (rg_infos) |info| {
            @memcpy(all_bufs[info.start .. info.start + info.count], info.bufs);
            @memcpy(all_chunks[info.start .. info.start + info.count], info.chunks);
        }

        // Decode all columns from all row groups in a single parallel batch
        if (builtin.single_threaded or total_columns <= 1) {
            for (0..total_columns) |i| {
                decodeColumnTask(all_bufs[i], all_chunks[i], self.metadata, self.ts_allocator.allocator(), &results[i]);
            }
        } else {
            var group: std.Io.Group = .init;
            errdefer group.cancel(io);
            for (0..total_columns) |i| {
                try group.concurrent(io, decodeColumnTask, .{
                    all_bufs[i],
                    all_chunks[i],
                    self.metadata,
                    self.ts_allocator.allocator(),
                    &results[i],
                });
            }
            try group.await(io);
        }

        // Partition results back into per-row-group Chunks
        var frame_chunks = try std.array_list.Managed(Chunk).initCapacity(self.allocator, num_rg);
        for (rg_infos) |info| {
            var cols = try std.array_list.Managed(series.Series).initCapacity(self.allocator, info.count);
            for (results[info.start .. info.start + info.count]) |r| {
                if (r.err) return error.ColumnDecodeFailed;
                try cols.append(r.series.?);
            }
            try frame_chunks.append(Chunk{ .columns = cols });
        }

        return Frame{ .chunks = frame_chunks };
    }

    pub fn readRowGroupSelective(self: *ParquetReader, io: std.Io, row_group_idx: usize, column_names: ?[]const []const u8) !Chunk {
        if (row_group_idx >= self.metadata.row_groups.items.len) {
            return error.RowGroupIndexOutOfBounds;
        }
        const rg = self.metadata.row_groups.items[row_group_idx];
        const info = try self.collectColumnChunks(rg, column_names);
        defer self.allocator.free(info.chunks);
        defer self.allocator.free(info.bufs);

        const n = info.chunks.len;
        const results = try self.allocator.alloc(DecodeResult, n);
        defer self.allocator.free(results);
        @memset(results, .{ .series = null, .err = false });

        if (builtin.single_threaded or n <= 1) {
            for (0..n) |i| {
                decodeColumnTask(info.bufs[i], info.chunks[i], self.metadata, self.ts_allocator.allocator(), &results[i]);
            }
        } else {
            var group: std.Io.Group = .init;
            errdefer group.cancel(io);
            for (0..n) |i| {
                try group.concurrent(io, decodeColumnTask, .{
                    info.bufs[i],
                    info.chunks[i],
                    self.metadata,
                    self.ts_allocator.allocator(),
                    &results[i],
                });
            }
            try group.await(io);
        }

        var cols = try std.array_list.Managed(series.Series).initCapacity(self.allocator, n);
        for (results) |r| {
            if (r.err) return error.ColumnDecodeFailed;
            try cols.append(r.series.?);
        }
        return Chunk{ .columns = cols };
    }

    pub fn getColumnNames(self: *ParquetReader) !std.array_list.Managed([]u8) {
        var names = std.array_list.Managed([]u8).init(self.allocator);

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
pub fn readParquetSelective(io: std.Io, path: []const u8, column_names: ?[]const []const u8, allocator: std.mem.Allocator) !Frame {
    var reader = try ParquetReader.init(io, path, allocator);
    defer reader.deinit();

    return try reader.readAllRowGroupsSelective(io, column_names);
}

// Convenience function: Get column names from a parquet file
pub fn getParquetColumns(io: std.Io, path: []const u8, allocator: std.mem.Allocator) !std.array_list.Managed([]u8) {
    var reader = try ParquetReader.init(io, path, allocator);
    defer reader.deinit();

    return try reader.getColumnNames();
}

// Main readParquet function - uses optimized ParquetReader approach
pub fn readParquet(io: std.Io, path: []const u8, allocator: std.mem.Allocator) !Frame {
    var reader = try ParquetReader.init(io, path, allocator);
    defer reader.deinit();

    return try reader.readAllRowGroupsSelective(io, null);
}
