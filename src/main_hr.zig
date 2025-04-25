const std = @import("std");
const builtin = @import("builtin");

const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const sgfx = sokol.gfx;
const simgui = sokol.imgui;

const hrconf = @import("hot_reload_config");
const build_opt = @import("options");

var allocator = std.heap.c_allocator;
var filename: []const u8 = undefined;
var dynlib: DynamicLibrary = undefined;
var watcher: FileWatcher = undefined;

var gs: *anyopaque = undefined;
var mem_size: usize = 0;

var init: *const fn (*std.mem.Allocator) callconv(.C) ?*anyopaque = undefined;
var deinit: *const fn (*std.mem.Allocator, *anyopaque) callconv(.C) void = undefined;
var frame: *const fn (*anyopaque) callconv(.C) void = undefined;
var event: *const fn (?*const sokol.app.Event) callconv(.C) void = undefined;
var memory_size: *const fn () callconv(.C) usize = undefined;

pub fn main() !void {
    sokol.app.run(.{
        .init_cb = m_init,
        .frame_cb = m_frame,
        .cleanup_cb = m_cleanup,
        .event_cb = m_event,
        .window_title = build_opt.app_name ++ " [Hotreloading]",
        .width = 800,
        .height = 600,
        .logger = .{ .func = sokol.log.func },
        .icon = .{ .sokol_default = true },
        .sample_count = 4,
    });
}

fn m_init() callconv(.C) void {
    filename = create_lib_name(hrconf.lib_name) catch {
        std.debug.print("error: cannot initialize", .{});
        sokol.app.quit();
        return;
    };
    watcher = FileWatcher.init(filename, .ChangeTime) catch {
        std.debug.print("error: cannot initialize", .{});
        sokol.app.quit();
        return;
    };
    dynlib = DynamicLibrary.load(allocator, filename) catch {
        std.debug.print("error: cannot initialize", .{});
        sokol.app.quit();
        return;
    };

    load_gameapi(&dynlib) catch |err| {
        std.debug.print("error: cannot bind functions, err: {any}", .{err});
        sokol.app.quit();
        return;
    };
    mem_size = memory_size();

    gs = init(&allocator) orelse {
        std.debug.print("error: cannot init game", .{});
        sokol.app.quit();
        return;
    };
}

fn m_frame() callconv(.C) void {
    frame(gs);
    check_dynlib() catch |err| {
        std.debug.print("error: hotreload attempt failed, err: {any}", .{err});
    };
}

fn check_dynlib() !void {
    if (try watcher.did_file_change()) {
        std.debug.print("change detected, reloading code...\n", .{});
        try dynlib.unload();
        dynlib = try DynamicLibrary.load(allocator, filename);
        try load_gameapi(&dynlib);

        const new_mem_size = memory_size();
        if (new_mem_size != mem_size) {
            std.debug.print("memory layout for game state has changed, reinitializing the game...\n", .{});
            mem_size = new_mem_size;
            deinit(&allocator, gs);
            gs = init(&allocator) orelse return error.CanNotInitGame;
        }
    }
}

fn m_cleanup() callconv(.C) void {
    deinit(&allocator, gs);
    dynlib.unload() catch {};
    allocator.free(filename);
}

fn m_event(e: ?*const sokol.app.Event) callconv(.C) void {
    event(e);
}

/// Creates appropriate dynamic library filename per platform from given lib_name
fn create_lib_name(lib_name: []const u8) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}.dll", .{lib_name}),
        .macos => try std.fmt.allocPrint(allocator, "lib{s}.dylib", .{lib_name}),
        .linux => try std.fmt.allocPrint(allocator, "lib{s}.so", .{lib_name}),
        else => unreachable,
    };
}

/// Loads the dynlib given in path, either an absolute path or RPath
fn load_gameapi(dlib: *DynamicLibrary) !void {
    init = try dlib.lookup(@TypeOf(init), "init");
    deinit = try dlib.lookup(@TypeOf(deinit), "deinit");
    frame = try dlib.lookup(@TypeOf(frame), "frame");
    event = try dlib.lookup(@TypeOf(event), "event");
    memory_size = try dlib.lookup(@TypeOf(memory_size), "memory_size");
}

// DynamicLibrary
//
// I think macOS caches dynamic libraries, which is a bummer if you're trying to do hot reloads.
// Therefore, when we want to load a dynamic library, we first create a copy of the file
// using the md5 hash as a temp filename. Then we load the dynamic library. The temp file is deleted
// when the library is unloaded.
const DynamicLibrary = struct {
    allocator: std.mem.Allocator,
    lib_abs_path: []const u8,
    tmplib_abs_path: []const u8,
    dynlib: std.DynLib,

    const READ_BUFF_SIZE = 1024 * 1024;

    pub fn load(alloc: std.mem.Allocator, lib_filename: []const u8) !DynamicLibrary {
        const cwd = try std.fs.realpathAlloc(alloc, "./");
        defer alloc.free(cwd);

        const hash = try DynamicLibrary.get_file_hash(lib_filename);
        const tmp_filename = try DynamicLibrary.create_lib_name(alloc, &std.fmt.bytesToHex(hash, .lower));
        defer alloc.free(tmp_filename);

        const src = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ cwd, lib_filename });
        const dest = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ cwd, tmp_filename });

        try std.fs.copyFileAbsolute(src, dest, .{});

        const dlib = try std.DynLib.open(dest);

        return DynamicLibrary{
            .allocator = alloc,
            .lib_abs_path = src,
            .tmplib_abs_path = dest,
            .dynlib = dlib,
        };
    }

    pub fn unload(d: *DynamicLibrary) !void {
        d.dynlib.close();

        try std.fs.deleteFileAbsolute(d.tmplib_abs_path);

        d.allocator.free(d.tmplib_abs_path);
        d.allocator.free(d.lib_abs_path);
    }

    pub fn lookup(d: *DynamicLibrary, comptime T: type, name: [:0]const u8) !T {
        return d.dynlib.lookup(T, name) orelse error.Unresolved;
    }

    /// Opens $CWD/path and creates md5 hash of the file, outputs to out buf
    fn get_file_hash(path: []const u8) ![16]u8 {
        var read_buffer: [READ_BUFF_SIZE]u8 = .{0} ** READ_BUFF_SIZE;

        var hasher = std.crypto.hash.Md5.init(.{});

        var file = try std.fs.cwd().openFile(path, .{});
        var read_size = try file.read(&read_buffer);
        while (read_size == read_buffer.len) {
            hasher.update(&read_buffer);
            read_size = try file.read(&read_buffer);
        }
        hasher.update(&read_buffer);

        var out: [16]u8 = .{0} ** 16;
        hasher.final(&out);
        return out;
    }

    /// Creates appropriate dynamic library filename per platform from given lib_name
    fn create_lib_name(alloc: std.mem.Allocator, lib_name: []const u8) ![]const u8 {
        return switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(alloc, "{s}.dll", .{lib_name}),
            .macos => try std.fmt.allocPrint(alloc, "lib{s}.dylib", .{lib_name}),
            .linux => try std.fmt.allocPrint(alloc, "lib{s}.so", .{lib_name}),
            else => unreachable,
        };
    }
};

// FileWatcher
//
// I think macOS caches dynamic libraries, which is a bummer if you're trying to do hot reloads.
// Therefore, when we want to load a dynamic library, we first create a copy of the file
// using the md5 hash as a temp filename. Then we load the dynamic library. The temp file is deleted
// when the library is unloaded.
const FileWatcher = struct {
    pub const Mode = enum {
        Hash,
        ChangeTime,
    };

    const READ_BUFF_SIZE = 1024 * 1024;

    path: []const u8,
    mode: Mode,

    last_hash: [16]u8 = undefined,
    last_ctime_secs: isize = undefined,

    pub fn init(abs_path: []const u8, mode: Mode) !FileWatcher {
        var f = FileWatcher{
            .path = abs_path,
            .mode = mode,
        };
        switch (mode) {
            .Hash => f.last_hash = try get_file_hash(abs_path),
            .ChangeTime => f.last_ctime_secs = try get_file_changetime(abs_path),
        }
        return f;
    }

    /// returns true only once if the file has changed since last invocation of did_file_change or init
    pub fn did_file_change(f: *FileWatcher) !bool {
        switch (f.mode) {
            .Hash => {
                const h = try get_file_hash(f.path);
                if (!std.mem.eql(u8, &h, &f.last_hash)) {
                    f.last_hash = h;
                    return true;
                } else {
                    return false;
                }
            },
            .ChangeTime => {
                const ctime = try get_file_changetime(f.path);
                if (ctime != f.last_ctime_secs) {
                    f.last_ctime_secs = ctime;
                    return true;
                } else {
                    return false;
                }
            },
        }
    }

    /// Opens $CWD/path and creates md5 hash of the file, outputs to out buf
    fn get_file_hash(path: []const u8) ![16]u8 {
        var read_buffer: [READ_BUFF_SIZE]u8 = .{0} ** READ_BUFF_SIZE;

        var hasher = std.crypto.hash.Md5.init(.{});

        var file = try std.fs.cwd().openFile(path, .{});
        var read_size = try file.read(&read_buffer);
        while (read_size == read_buffer.len) {
            hasher.update(&read_buffer);
            read_size = try file.read(&read_buffer);
        }
        hasher.update(&read_buffer);

        var out: [16]u8 = .{0} ** 16;
        hasher.final(&out);
        return out;
    }

    /// Not in use, can be used to check if the file is changed on posix systems
    /// fstat not supported on Windows for the time being and we have a multi-threaded
    /// hash checker in place, so no need for the time being.
    fn get_file_changetime(path: []const u8) !isize {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const fstat = try std.posix.fstat(file.handle);
        return fstat.ctimespec.sec;
    }
};
