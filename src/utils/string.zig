const std = @import("std");

pub const LargeString: type = struct {
    len: u32,
    prefix: [4]u8,
    trailing: ?[*]const u8,

    const Self = LargeString;

    pub fn init(str: []const u8, allocator: std.mem.Allocator) !Self {
        if (str.len <= 4) {
            return Self{ .len = @intCast(str.len), .prefix = str[0..4].*, .trailing = null };
        } else {
            const trailing = try allocator.alloc(u8, str.len - 4);
            @memcpy(trailing, str[4..]);
            return Self{ .len = @intCast(str.len), .prefix = str[0..4].*, .trailing = trailing.ptr };
        }
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.trailing) |t| {
            allocator.free(t[0 .. self.len - 4]);
        }
    }

    pub fn fmt(self: Self) ![]const u8 {
        if (self.trailing) |t| {
            const mx = @min(self.len, 16);
            var buf: [16]u8 = undefined;
            @memcpy(buf[0..4], self.prefix[0..]);
            @memcpy(buf[4..mx], t[0 .. mx - 4]);
            return buf[0..mx];
        } else {
            return self.prefix[0..self.len];
        }
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.len != other.len) return false;
        if (std.mem.eql(u8, &self.prefix, &other.prefix)) {
            if (self.len <= 4) return true;

            if (self.trailing) |st| {
                if (other.trailing) |ot| {
                    return std.mem.eql(u8, st.*, ot.*);
                }
            }
        }
        return false;
    }
};

test "mstring" {
    const allocator = std.testing.allocator;

    std.debug.print("\nSize: {}", .{@sizeOf(LargeString)});
    const v = "Hello world";
    const m = try LargeString.init(v, allocator);
    defer m.deinit(allocator);

    std.debug.print("{s}", .{try m.fmt()});
}
