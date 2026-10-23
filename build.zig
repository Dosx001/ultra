const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.addTranslateC(.{
        .root_source_file = b.path("include/wayland.h"),
        .target = target,
        .optimize = optimize,
    });
    wayland.linkSystemLibrary("wlroots-0.20", .{});
    wayland.linkSystemLibrary("wayland-server", .{});
    wayland.linkSystemLibrary("xkbcommon", .{});
    const protocols = [_][]const u8{
        "wlr-layer-shell-unstable-v1",
    };
    for (protocols) |proto| {
        const xml = b.fmt(
            "wlr-protocols/unstable/{s}.xml",
            .{proto},
        );
        const proto_step = b.addSystemCommand(&.{
            "wayland-scanner",
            "server-header",
            xml,
        });
        proto_step.addFileInput(b.path(xml));
        const header = proto_step.addOutputFileArg(
            b.fmt("{s}-protocol.h", .{proto}),
        );
        wayland.addIncludePath(header.dirname());
    }
    const log = b.addTranslateC(.{
        .root_source_file = b.path("include/log.h"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "ultra",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "wayland",
                    .module = wayland.createModule(),
                },
                .{
                    .name = "log",
                    .module = log.createModule(),
                },
            },
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
