const c = @import("c");
const std = @import("std");

const cursor_mode = enum {
    CURSOR_MOVE,
    CURSOR_PASSTHROUGH,
    CURSOR_RESIZE,
};

const Server = struct {
    allocator: ?*c.wlr_allocator = null,
    backend: ?*c.wlr_backend = null,
    renderer: ?*c.wlr_renderer = null,
    scene: ?*c.wlr_scene = null,
    scene_layout: ?*c.wlr_scene_output_layout = null,
    wl_display: ?*c.wl_display,

    new_xdg_popup: c.wl_listener = undefined,
    new_xdg_toplevel: c.wl_listener = undefined,
    toplevels: c.wl_list = undefined,
    xdg_shell: ?*c.wlr_xdg_shell = null,

    cursor: ?*c.wlr_cursor = null,
    cursor_aixs: c.wl_listener = undefined,
    cursor_button: c.wl_listener = undefined,
    cursor_frame: c.wl_listener = undefined,
    cursor_mgr: ?*c.wlr_xcursor_manager = null,
    cursor_motion: c.wl_listener = undefined,
    cursor_motion_absolute: c.wl_listener = undefined,

    cursor_mode: cursor_mode = .CURSOR_MOVE,
    grab_geobox: c.wlr_box = undefined,
    grab_x: f64 = 0.0,
    grab_y: f64 = 0.0,
    grabbed_toplevel: ?*Toplevel = null,
    keyboards: c.wl_list = undefined,
    new_input: c.wl_listener = undefined,
    pointer_focus_change: c.wl_listener = undefined,
    request_cursor: c.wl_listener = undefined,
    request_set_selection: c.wl_listener = undefined,
    resize_edges: u32 = 0,
    seat: ?*c.wlr_seat = null,

    new_output: c.wl_listener = undefined,
    output_layout: ?*c.wlr_output_layout = null,
    outputs: c.wl_list = undefined,
};

const Output = struct {
    destroy: c.wl_listener,
    events: struct {
        frame: c.wl_signal,
        request_state: c.wl_listener,
        destroy: c.wl_listener,
    },
    frame: c.wl_listener,
    link: c.wl_list,
    request_state: c.wl_listener,
    server: ?*Server,
    wlr_output: ?*c.wlr_output,
};

const Toplevel = struct {
    commmit: c.wl_listener,
    destroy: c.wl_listener,
    link: c.wl_list,
    map: c.wl_listener,
    request_fullscreen: c.wl_listener,
    request_maximize: c.wl_listener,
    request_move: c.wl_listener,
    request_resize: c.wl_listener,
    scene_tree: ?*c.wlr_scene_tree,
    server: ?*Server,
    unmap: c.wl_listener,
    xdg_toplevel: ?*c.wlr_xdg_toplevel,
};

const Popup = struct {
    commit: c.wl_listener,
    destroy: c.wl_listener,
    xdg_popup: ?*c.wlr_xdg_popup,
};

const Keyboard = struct {
    destroy: c.wl_listener,
    key: c.wl_listener,
    key_repeat: c.wl_listener,
    link: c.wl_list,
    modifiers: c.wl_listener,
    server: ?*Server,
    wlr_keyboard: ?*c.wlr_keyboard,
};

pub fn init() !Server {
    var server = Server{
        .wl_display = c.wl_display_create(),
    };
    server.backend = c.wlr_backend_autocreate(c.wl_display_get_event_loop(server.wl_display), null);
    if (server.backend == null) {
        std.log.err("failed to create wlr_backend", .{});
        return error.BackendCreation;
    }
    server.renderer = c.wlr_renderer_autocreate(server.backend);
    if (server.renderer == null) {
        std.log.err("failed to create wlr_renderer", .{});
        return error.RendererCreation;
    }
    _ = c.wlr_renderer_init_wl_display(server.renderer, server.wl_display);
    server.allocator = c.wlr_allocator_autocreate(server.backend, server.renderer);
    if (server.allocator == null) {
        std.log.err("failed to create wlr_allocator", .{});
        return error.AllocatorCreation;
    }
    _ = c.wlr_compositor_create(server.wl_display, 5, server.renderer);
    _ = c.wlr_subcompositor_create(server.wl_display);
    _ = c.wlr_data_device_manager_create(server.wl_display);
    server.output_layout = c.wlr_output_layout_create(server.wl_display);
    c.wl_list_init(&server.outputs);
    server.new_output.notify = server_new_output;
    return server;
}

fn output_frame(_: ?*c.wl_listener, _: ?*anyopaque) callconv(.c) void {}

fn server_new_output(_: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    // const s: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_output: ?*c.wlr_output = @ptrCast(@alignCast(data));
    std.log.info("new output: {any}", .{wlr_output});
    // c.wlr_output_init_render(wlr_output, s.allocator, s.renderer);
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    c.wlr_output_state_set_enabled(&state, true);
    const mode = c.wlr_output_preferred_mode(wlr_output);
    if (mode != null) {
        c.wlr_output_state_set_mode(&state, mode);
    }
    _ = c.wlr_output_commit_state(wlr_output, &state);
    c.wlr_output_state_finish(&state);
    var output: *Output = std.mem.Allocator.create(std.heap.page_allocator, Output) catch unreachable;
    output.link.next = null;
    output.link.prev = null;
    output.server = null;
    output.wlr_output = wlr_output;
    output.frame.notify = output_frame;
    // c.wl_list_insert(&server.outputs, &output.link);
}
