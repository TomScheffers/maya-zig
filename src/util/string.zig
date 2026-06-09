const std = @import("std");

pub const SmallString: type = struct {
    len: u32,
    value: [12]u8,

    const Self = LargeString;

    pub fn init(str: []const u8) !Self {
        if (str.len <= 12) {
            return Self{ .len = @intCast(str.len), .value = str[0..12].* };
        } else {
            unreachable;
        }
    }
};

pub const LargeString: type = struct {
    length: u32,
    prefix: [4]u8,
    trailing: ?[*]const u8,

    const Self = LargeString;

    pub fn init(str: []const u8, allocator: std.mem.Allocator) !Self {
        var prefix: [4]u8 = undefined;
        @memcpy(prefix[0..@min(str.len, 4)], str[0..@min(str.len, 4)]);
        if (str.len <= 4) {
            return Self{ .length = @intCast(str.len), .prefix = prefix, .trailing = null };
        } else {
            const trailing = try allocator.alloc(u8, str.len - 4);
            @memcpy(trailing, str[4..]);
            return Self{ .length = @intCast(str.len), .prefix = prefix, .trailing = trailing.ptr };
        }
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.trailing) |t| {
            allocator.free(t[0 .. self.length - 4]);
        }
    }

    pub fn len(self: Self) usize {
        return @as(usize, self.length);
    }

    pub fn fmt(self: Self, comptime N: usize) [N]u8 {
        var buf: [N]u8 = undefined;
        if (self.trailing) |t| {
            const mx = @min(self.length, N);
            @memcpy(buf[0..4], self.prefix[0..]);
            @memcpy(buf[4..mx], t[0 .. mx - 4]);
        } else {
            @memcpy(buf[0..4], self.prefix[0..]);
        }
        for (self.length..N) |i| {
            buf[i] = ' ';
        }
        return buf;
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.length != other.length) return false;
        if (std.mem.eql(u8, &self.prefix, &other.prefix)) {
            if (self.length <= 4) return true;

            if (self.trailing) |st| {
                if (other.trailing) |ot| {
                    return std.mem.eql(u8, st.*, ot.*);
                }
            }
        }
        return false;
    }
};

const String: type = struct {
    len: u32,
    prefix: [4]u8,
    trailing: ?[*]const u8, // Will store a pointer when the string length > 12, otherwise it's `null` and data is inline

    pub fn init(str: []const u8, allocator: std.mem.Allocator) !String {
        var prefix: [4]u8 = undefined;
        @memcpy(prefix[0..@min(str.len, 4)], str[0..@min(str.len, 4)]);

        var result = String{ .len = @intCast(str.len), .prefix = prefix, .trailing = null };
        if (str.len <= 4) {
            result.trailing = null;
        } else if (str.len <= 12) {
            // Store the data inline, no need for a pointer
            var trail: [8]u8 = undefined;
            @memcpy(trail[0 .. str.len - 4], str[4..]);
            result.trailing = trail[0..];
            std.debug.print("\nTrail: {s}", .{result.trailing.?[0..8]});
            // @as(*[8]u8, @ptrCast(result.trailing)).* = trail;
        } else {
            // For longer strings, store the pointer to the trailing data
            const trail = try allocator.alloc(u8, str.len - 4);
            @memcpy(trail, str[4..]);
            result.trailing = trail.ptr;
            std.debug.print("\nTrail: {s}", .{result.trailing.?[0..8]});
        }
        return result;
    }

    pub fn deinit(self: String, allocator: std.mem.Allocator) void {
        if (self.length > 12) {
            allocator.free(self.trailing.?[0 .. self.length - 4]);
        }
    }

    pub fn fmt(self: String, comptime N: usize) [N]u8 {
        var buf: [N]u8 = undefined;
        if (self.length <= 4) {
            @memcpy(buf[0..4], self.prefix[0..]);
        } else if (self.length <= 12) {
            const mx = @min(self.length, N);
            @memcpy(buf[0..4], self.prefix[0..]);
            const trail: *[8]u8 = @ptrCast(@constCast(self.trailing.?)); // Trailing is not actually a pointer
            @memcpy(buf[4..mx], trail[0 .. mx - 4]);
        } else {
            const mx = @min(self.length, N);
            @memcpy(buf[0..4], self.prefix[0..]);
            @memcpy(buf[4..mx], self.trailing.?[0 .. mx - 4]);
        }
        for (self.length..N) |i| {
            buf[i] = ' ';
        }
        return buf;
    }
};

test "mstring" {
    const allocator = std.testing.allocator;

    std.debug.print("\nSize: {}", .{@sizeOf(SmallString)});
    std.debug.print("\nSize: {}", .{@sizeOf(LargeString)});
    std.debug.print("\nSize: {}", .{@sizeOf(String)});

    const s1 = try LargeString.init("Tom", allocator);
    defer s1.deinit(allocator);
    std.debug.print("\ns1:{s}", .{s1.fmt(16)});

    const s2 = try LargeString.init("Hello world", allocator);
    defer s2.deinit(allocator);
    std.debug.print("\ns2:{s}", .{s2.fmt(16)});

    const s3 = try LargeString.init("Hello ziggies!!", allocator);
    defer s3.deinit(allocator);
    std.debug.print("\ns3:{s}", .{s3.fmt(16)});
}
