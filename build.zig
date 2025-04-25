const std = @import("std");

const ExeName = "game";

const AppName = "Sokol + ImGUI Hotreloading Template";
const SemanticVersion = "0.0.0";

pub fn build_hotreload(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    var step_hotreload = b.step("hotreload", "builds a set of shared libraries to be used in hotreloading");

    // ===========================================
    // Dependencies
    // ===========================================
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
        .dynamic_linkage = true,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
        .dynamic_linkage = true,
    });
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path("src"));
    dep_sokol.artifact("sokol_clib").linkLibrary(dep_cimgui.artifact("cimgui_clib"));

    var step_install_sokolclib = b.addInstallArtifact(dep_sokol.artifact("sokol_clib"), .{ .dest_dir = .{ .override = .{ .custom = "hotreload" } } });
    step_hotreload.dependOn(&step_install_sokolclib.step);

    var step_install_cimguiclib = b.addInstallArtifact(dep_cimgui.artifact("cimgui_clib"), .{ .dest_dir = .{ .override = .{ .custom = "hotreload" } } });
    step_hotreload.dependOn(&step_install_cimguiclib.step);

    // ===========================================
    // Build Game Shared library
    // ===========================================
    const mod_game = b.addModule("mod_game", .{
        .root_source_file = b.path("src/game/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = "cimgui", .module = dep_cimgui.module("cimgui") },
        },
    });
    try addOptions(b, mod_game);

    const lib_game = b.addLibrary(.{
        .name = "game",
        .linkage = .dynamic,
        .root_module = mod_game,
    });

    var step_install_game = b.addInstallArtifact(lib_game, .{ .dest_dir = .{ .override = .{ .custom = "hotreload" } } });
    step_hotreload.dependOn(&step_install_game.step);

    // ===========================================
    // Build app executable
    // ===========================================
    const mod_app = b.addModule("mod_app", .{
        .root_source_file = b.path("src/main_hr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = "cimgui", .module = dep_cimgui.module("cimgui") },
        },
    });
    try addOptions(b, mod_app);

    var opt = b.addOptions();
    opt.addOption([]const u8, "lib_name", lib_game.name);
    mod_app.addOptions("hot_reload_config", opt);

    const exe_app = b.addExecutable(.{
        .name = ExeName ++ "-hr",
        .root_module = mod_app,
    });
    exe_app.linkLibrary(dep_sokol.artifact("sokol_clib"));
    exe_app.linkLibrary(dep_cimgui.artifact("cimgui_clib"));

    var step_install_app = b.addInstallArtifact(exe_app, .{ .dest_dir = .{ .override = .{ .custom = "hotreload" } } });
    step_hotreload.dependOn(&step_install_app.step);

    b.getInstallStep().dependOn(step_hotreload);
}

fn build_static(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    var step_static = b.step("static", "builds a statically linked executable");

    // ===========================================
    // Dependencies
    // ===========================================
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path("src"));
    dep_sokol.artifact("sokol_clib").linkLibrary(dep_cimgui.artifact("cimgui_clib"));

    // ===========================================
    // Build Game Shared library
    // ===========================================
    const mod_game = b.addModule("mod_game", .{
        .root_source_file = b.path("src/game/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = "cimgui", .module = dep_cimgui.module("cimgui") },
        },
    });
    try addOptions(b, mod_game);

    const lib_game = b.addLibrary(.{
        .name = "game",
        .linkage = .static,
        .root_module = mod_game,
    });
    step_static.dependOn(&lib_game.step);

    // ===========================================
    // Build app executable
    // ===========================================
    const mod_app = b.addModule("mod_app", .{
        .root_source_file = b.path("src/main_static.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = "cimgui", .module = dep_cimgui.module("cimgui") },
        },
    });
    try addOptions(b, mod_app);

    // add lib_name
    var opt = b.addOptions();
    opt.addOption([]const u8, "lib_name", lib_game.name);
    mod_app.addOptions("hot_reload_config", opt);

    const exe_app = b.addExecutable(.{
        .name = ExeName,
        .root_module = mod_app,
    });
    exe_app.linkLibrary(lib_game);
    exe_app.linkLibrary(dep_sokol.artifact("sokol_clib"));
    exe_app.linkLibrary(dep_cimgui.artifact("cimgui_clib"));

    var step_install_app = b.addInstallArtifact(exe_app, .{ .dest_dir = .{ .override = .{ .custom = "static" } } });
    step_static.dependOn(&step_install_app.step);

    b.getInstallStep().dependOn(step_static);
}

fn addOptions(b: *std.Build, module: *std.Build.Module) !void {
    var opt = b.addOptions();
    opt.addOption([]const u8, "version", SemanticVersion);
    opt.addOption([]const u8, "app_name", AppName);
    module.addOptions("options", opt);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    build_static(b, target, optimize);
    build_hotreload(b, target, optimize);
}
