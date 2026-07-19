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

    cursor_mode: cursor_mode = .CURSOR_PASSTHROUGH,
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
    c.wl_signal_add(&server.backend.?.events.new_output, &server.new_output);
    server.scene = c.wlr_scene_create();
    server.scene_layout = c.wlr_scene_attach_output_layout(server.scene, server.output_layout);
    c.wl_list_init(&server.toplevels);
    server.xdg_shell = c.wlr_xdg_shell_create(server.wl_display, 3);
    server.new_xdg_toplevel.notify = server_new_xdg_toplevel;
    c.wl_signal_add(&server.xdg_shell.?.events.new_toplevel, &server.new_xdg_toplevel);
    server.new_xdg_popup.notify = server_new_xdg_popup;
    c.wl_signal_add(&server.xdg_shell.?.events.new_popup, &server.new_xdg_popup);
    server.cursor = c.wlr_cursor_create();
    c.wlr_cursor_attach_output_layout(server.cursor, server.output_layout);
    server.cursor_mgr = c.wlr_xcursor_manager_create(null, 24);
    server.cursor_motion.notify = server_cursor_motion;
    return server;
}

fn output_frame(listener: ?*c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const output: *Output = @fieldParentPtr("frame", listener.?);
    const scene = output.server.?.scene;
    const scene_output: *c.wlr_scene_output = c.wlr_scene_get_scene_output(scene, output.wlr_output);
    _ = c.wlr_scene_output_commit(scene_output, null);
    var now: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(scene_output, &now);
}

fn server_new_output(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_output: ?*c.wlr_output = @ptrCast(@alignCast(data));
    _ = c.wlr_output_init_render(wlr_output, server.allocator, server.renderer);
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    c.wlr_output_state_set_enabled(&state, true);
    const mode = c.wlr_output_preferred_mode(wlr_output);
    if (mode != null) {
        c.wlr_output_state_set_mode(&state, mode);
    }
    _ = c.wlr_output_commit_state(wlr_output, &state);
    c.wlr_output_state_finish(&state);
    var output: *Output = std.mem.Allocator.create(std.heap.c_allocator, Output) catch unreachable;
    output.server = server;
    output.wlr_output = wlr_output;
    output.frame.notify = output_frame;
    c.wl_signal_add(&wlr_output.?.events.frame, &output.frame);
    c.wl_signal_add(&wlr_output.?.events.request_state, &output.request_state);
    c.wl_signal_add(&wlr_output.?.events.frame, &output.destroy);
    c.wl_list_insert(&server.outputs, &output.link);
    const l_output = c.wlr_output_layout_add_auto(server.output_layout, wlr_output);
    const scene_output = c.wlr_scene_output_create(server.scene, wlr_output);
    c.wlr_scene_output_layout_add_output(server.scene_layout, l_output, scene_output);
}

fn focus_toplevel(toplevel: ?*Toplevel) void {
    if (toplevel == null) {
        return;
    }
    const server = toplevel.?.server;
    const seat = server.?.seat;
    const prev_surface = seat.?.keyboard_state.focused_surface;
    const surface = toplevel.?.xdg_toplevel.?.base.*.surface;
    if (prev_surface == surface) {
        return;
    }
    if (prev_surface != null) {
        const prev_toplevel = c.wlr_xdg_toplevel_try_from_wlr_surface(prev_surface);
        if (prev_toplevel != null) {
            _ = c.wlr_xdg_toplevel_set_activated(prev_toplevel, false);
        }
    }
    c.wlr_scene_node_raise_to_top(&toplevel.?.scene_tree.?.node);
    c.wl_list_remove(&toplevel.?.link);
    c.wl_list_insert(&server.?.toplevels, &toplevel.?.link);
    _ = c.wlr_xdg_toplevel_set_activated(toplevel.?.xdg_toplevel, true);
    const keyboard = c.wlr_seat_get_keyboard(seat);
    if (keyboard != null) {
        c.wlr_seat_keyboard_notify_enter(
            seat,
            surface,
            @ptrCast(&keyboard.*.keycodes),
            keyboard.*.num_keycodes,
            &keyboard.*.modifiers,
        );
    }
}

fn xdg_toplevel_map(listener: ?*c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("map", listener.?);
    c.wl_list_insert(&toplevel.?.server.?.toplevels, &toplevel.?.link);
    focus_toplevel(toplevel);
}

fn server_new_xdg_toplevel(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_xdg_toplevel", listener.?);
    const xdg_toplevel: ?*c.wlr_xdg_toplevel = @ptrCast(@alignCast(data));
    var toplevel = std.mem.Allocator.create(
        std.heap.c_allocator,
        Toplevel,
    ) catch unreachable;
    toplevel.server = server;
    toplevel.xdg_toplevel = xdg_toplevel;
    toplevel.scene_tree = c.wlr_scene_xdg_surface_create(
        &toplevel.server.?.scene.?.tree,
        xdg_toplevel.?.base,
    );
    toplevel.*.scene_tree.?.node.data = toplevel;
    xdg_toplevel.?.base.*.data = toplevel.scene_tree;
    toplevel.map.notify = xdg_toplevel_map;
}

fn xdg_popup_commit(listener: ?*c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const popup: ?*Popup = @fieldParentPtr("commit", listener.?);
    if (popup.?.xdg_popup.?.base.*.initial_commit) {
        _ = c.wlr_xdg_surface_schedule_configure(popup.?.xdg_popup.?.base);
    }
}

fn xdg_popup_destroy(listener: ?*c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const popup: ?*Popup = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&popup.?.commit.link);
    c.wl_list_remove(&popup.?.destroy.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, popup.?);
}

fn server_new_xdg_popup(_: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const xdg_popup: ?*c.wlr_xdg_popup = @ptrCast(@alignCast(data));
    var popup = std.mem.Allocator.create(std.heap.c_allocator, Popup) catch unreachable;
    popup.xdg_popup = xdg_popup;
    const parent = c.wlr_xdg_surface_try_from_wlr_surface(xdg_popup.?.parent);
    if (parent == null) {
        return;
    }
    xdg_popup.?.base.*.data = c.wlr_scene_xdg_surface_create(
        @ptrCast(@alignCast(parent.*.data)),
        xdg_popup.?.base,
    );
    popup.commit.notify = xdg_popup_commit;
    c.wl_signal_add(&xdg_popup.?.base.*.surface.*.events.commit, &popup.commit);
    popup.destroy.notify = xdg_popup_destroy;
    c.wl_signal_add(&xdg_popup.?.events.destroy, &popup.destroy);
}

fn process_cursor_motion(server: *Server, _: u32) void {
    if (server.cursor_mode == .CURSOR_MOVE) {
        c.wlr_scene_node_set_position(
            &server.grabbed_toplevel.?.scene_tree.?.node,
            @intFromFloat(server.cursor.?.x - server.grab_x),
            @intFromFloat(server.cursor.?.y - server.grab_y),
        );
        return;
    } else if (server.cursor_mode == .CURSOR_RESIZE) {
        return;
    }
}

fn server_cursor_motion(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion", listener.?);
    const event: *c.wlr_pointer_motion_event = @ptrCast(@alignCast(data));
    c.wlr_cursor_move(server.cursor, &event.pointer.*.base, event.delta_x, event.delta_y);
    process_cursor_motion(server, event.time_msec);
}
