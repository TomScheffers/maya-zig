//! One-off: zig build dump-parse-json
const std = @import("std");
const pg_query = @import("pg_query");

pub fn main() !void {
    const sql =
        \\SELECT o.id,
        \\       sum(i.qty)::int4 AS total,
        \\       count(*),
        \\       upper(c.name) AS customer_name
        \\FROM public.orders o
        \\INNER JOIN public.items i ON o.id = i.order_id
        \\LEFT JOIN public.customers c ON c.id = o.customer_id
        \\WHERE o.status = 'open'
        \\  AND i.qty > 100
        \\  AND o.id IN (SELECT order_id FROM public.archived WHERE year = 2024)
        \\  AND o.email IS NOT NULL
        \\  AND NOT c.active
        \\  AND (o.amount < 1000 OR o.discount IS NULL)
        \\GROUP BY o.id, c.name
        \\HAVING sum(i.qty) > 500
        \\ORDER BY total DESC, o.id
        \\LIMIT 10 OFFSET 5
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try pg_query.parse(allocator, sql);
    const json = switch (parsed) {
        .ok => |tree| tree,
        .err => |failure| {
            std.debug.print("parse error: {}\n", .{failure});
            return error.ParseFailed;
        },
    };
    defer allocator.free(json);

    std.debug.print("{s}\n", .{json});
}
