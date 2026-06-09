const std = @import("std");

const libpg_root = "vendor/libpg_query";

const extra_sources = [_][]const u8{
    "vendor/protobuf-c/protobuf-c.c",
    "vendor/xxhash/xxhash.c",
    "protobuf/pg_query.pb-c.c",
};

const source_dirs = [_][]const u8{
    "src",
    "src/postgres",
};

const c_flags_common = [_][]const u8{
    "-std=gnu11",
    "-fno-strict-aliasing",
    "-fwrapv",
    "-Wno-unused-function",
    "-Wno-unused-value",
    "-Wno-unused-variable",
    "-Wno-macro-redefined",
};

pub fn addStaticLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    var sources: std.ArrayList([]const u8) = .empty;
    defer sources.deinit(b.allocator);

    for (source_dirs) |dir| {
        try collectCSources(b, dir, &sources);
    }
    for (extra_sources) |rel| {
        try sources.append(b.allocator, try b.allocator.dupe(u8, rel));
    }

    const root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    var flags: std.ArrayList([]const u8) = .empty;
    defer flags.deinit(b.allocator);
    try flags.appendSlice(b.allocator, &c_flags_common);
    if (target.result.os.tag == .windows) {
        try flags.append(b.allocator, "-D_CRT_SECURE_NO_WARNINGS");
    }

    root_module.addCSourceFiles(.{
        .root = b.path(libpg_root),
        .files = sources.items,
        .flags = flags.items,
    });

    addModuleIncludePaths(b, root_module, target);

    return b.addLibrary(.{
        .name = "pg_query",
        .root_module = root_module,
        .linkage = .static,
    });
}

pub fn addModuleIncludePaths(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    module.addIncludePath(b.path(libpg_root));
    module.addIncludePath(b.path(libpg_root ++ "/vendor"));
    module.addIncludePath(b.path(libpg_root ++ "/src/include"));
    module.addIncludePath(b.path(libpg_root ++ "/src/postgres/include"));
    if (target.result.os.tag == .windows) {
        module.addIncludePath(b.path(libpg_root ++ "/src/postgres/include/port/win32"));
        module.addIncludePath(b.path(libpg_root ++ "/src/postgres/include/port/win32_msvc"));
    }
}

pub fn addTranslateIncludePaths(
    b: *std.Build,
    translate_c: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) void {
    translate_c.addIncludePath(b.path(libpg_root));
    translate_c.addIncludePath(b.path(libpg_root ++ "/vendor"));
    translate_c.addIncludePath(b.path(libpg_root ++ "/src/include"));
    translate_c.addIncludePath(b.path(libpg_root ++ "/src/postgres/include"));
    if (target.result.os.tag == .windows) {
        translate_c.addIncludePath(b.path(libpg_root ++ "/src/postgres/include/port/win32"));
        translate_c.addIncludePath(b.path(libpg_root ++ "/src/postgres/include/port/win32_msvc"));
    }
}

fn collectCSources(b: *std.Build, dir_path: []const u8, out: *std.ArrayList([]const u8)) !void {
    const io = b.graph.io;
    const full_path = try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ libpg_root, dir_path });
    var dir = b.build_root.handle.openDir(io, full_path, .{ .iterate = true }) catch |err| {
        std.log.err("failed to open libpg_query source dir '{s}': {}", .{ full_path, err });
        return err;
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".c")) continue;
        try out.append(b.allocator, try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ dir_path, entry.name }));
    }
}
