const std = @import("std");

pub fn readZstd(buf: []u8, allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var in: std.Io.Reader = .fixed(buf);
    var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{
        .verify_checksum = false,
        .window_len = std.compress.zstd.default_window_len,
    });
    _ = try zstd_stream.reader.streamRemaining(&out.writer);

    return try out.toOwnedSlice();
}
