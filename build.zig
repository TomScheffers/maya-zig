const std = @import("std");
const libpg_query = @import("build/libpg_query.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pg_query_lib = libpg_query.addStaticLibrary(b, target, optimize) catch @panic("failed to configure libpg_query");

    const translate_pg_query = b.addTranslateC(.{
        .root_source_file = b.path("vendor/libpg_query/pg_query.h"),
        .target = target,
        .optimize = optimize,
    });
    libpg_query.addTranslateIncludePaths(b, translate_pg_query, target);

    const pg_query_c = translate_pg_query.createModule();

    const maya_mod = b.addModule("maya", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "pg_query_c", .module = pg_query_c },
        },
    });
    maya_mod.linkLibrary(pg_query_lib);
    maya_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "maya",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "maya", .module = maya_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the maya CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Optional: zig build test -Dtest-filter=todo.expr
    // Multiple filters: zig build test -Dtest-filter=foo -Dtest-filter=bar
    // (compile-time filter; do not pass --test-filter to the test executable in 0.16+)
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const mod_tests = b.addTest(.{
        .root_module = maya_mod,
        .filters = test_filters,
    });
    mod_tests.root_module.linkLibrary(pg_query_lib);
    mod_tests.root_module.link_libc = true;

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
