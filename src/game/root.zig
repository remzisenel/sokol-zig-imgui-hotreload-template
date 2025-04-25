const std = @import("std");

const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const sgfx = sokol.gfx;
const simgui = sokol.imgui;

const ig = @import("cimgui");

const GameState = struct {
    gfx: struct {
        pass_action: sgfx.PassAction,
    },
};

pub export fn init(allocator: *std.mem.Allocator) callconv(.C) ?*anyopaque {
    // initialize sokol-gfx
    sgfx.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .no_default_font = true,
        .logger = .{ .func = slog.func },
    });

    // initial clear color
    var gs = allocator.create(GameState) catch return null;
    gs.gfx.pass_action = .{};
    gs.gfx.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 },
    };
    return gs;
}

pub export fn deinit(allocator: *std.mem.Allocator, gs: *GameState) callconv(.C) void {
    allocator.destroy(gs);
    simgui.shutdown();
    sgfx.shutdown();
}

pub export fn frame(gs: *GameState) callconv(.C) void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    sgfx.beginPass(.{ .action = gs.gfx.pass_action, .swapchain = sglue.swapchain() });

    //=== UI CODE STARTS HERE
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    _ = ig.igBegin("Hello Dear ImGui!", 0, ig.ImGuiWindowFlags_None);
    _ = ig.igColorEdit3("Background", &gs.gfx.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
    _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    ig.igEnd();
    //=== UI CODE ENDS HERE

    simgui.render();
    sgfx.endPass();
    sgfx.commit();
}

pub export fn memory_size() callconv(.C) usize {
    return @sizeOf(GameState);
}

pub export fn event(ev: ?*const sapp.Event) callconv(.C) void {
    const e = ev.?;
    if (!simgui.handleEvent(e.*)) {
        // imgui did not handle the event, pass it down
        if (e.type == .KEY_DOWN) {
            if (e.key_code == .Q) {
                sapp.quit();
            }
        }
    }
}

const testing = std.testing;
test "basic functionality" {
    try testing.expect(1 == 1);
}
