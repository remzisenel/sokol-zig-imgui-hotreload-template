const std = @import("std");
const sokol = @import("sokol");

const build_opt = @import("options");

extern fn init(*std.mem.Allocator) callconv(.C) ?*anyopaque;
extern fn deinit(*std.mem.Allocator, *anyopaque) callconv(.C) void;
extern fn frame(*anyopaque) callconv(.C) void;
extern fn event(?*const sokol.app.Event) callconv(.C) void;

pub fn main() !void {
    sokol.app.run(.{
        .init_cb = m_init,
        .frame_cb = m_frame,
        .cleanup_cb = m_cleanup,
        .event_cb = m_event,
        .window_title = build_opt.app_name.ptr,
        .width = 800,
        .height = 600,
        .logger = .{ .func = sokol.log.func },
        .icon = .{ .sokol_default = true },
        .sample_count = 4,
    });
}

var allocator = std.heap.c_allocator;
var gs: *anyopaque = undefined;

fn m_init() callconv(.C) void {
    gs = init(&allocator) orelse {
        std.debug.print("error: cannot init game", .{});
        sokol.app.quit();
        return;
    };
}

fn m_frame() callconv(.C) void {
    frame(gs);
}

fn m_cleanup() callconv(.C) void {
    deinit(&allocator, gs);
}

fn m_event(e: ?*const sokol.app.Event) callconv(.C) void {
    event(e);
}
