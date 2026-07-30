const wl = @import("wayland");
const std = @import("std");

const CursorMode = enum {
    CURSOR_MOVE,
    CURSOR_PASSTHROUGH,
    CURSOR_RESIZE,
};

const Server = struct {
    allocator: ?*wl.wlr_allocator = null,
    backend: ?*wl.wlr_backend = null,
    renderer: ?*wl.wlr_renderer = null,
    scene: *wl.wlr_scene = undefined,
    scene_layout: ?*wl.wlr_scene_output_layout = null,
    session: ?*wl.wlr_session = null,
    wl_display: ?*wl.wl_display,

    new_xdg_popup: wl.wl_listener = .{ .notify = server_new_xdg_popup },
    new_xdg_toplevel: wl.wl_listener = .{ .notify = server_new_xdg_toplevel },
    toplevels: wl.wl_list = undefined,
    xdg_shell: *wl.wlr_xdg_shell = undefined,

    cursor: *wl.wlr_cursor = undefined,
    cursor_aixs: wl.wl_listener = .{ .notify = server_cursor_axis },
    cursor_button: wl.wl_listener = .{ .notify = server_cursor_button },
    cursor_frame: wl.wl_listener = .{ .notify = server_cursor_frame },
    cursor_mgr: *wl.wlr_xcursor_manager = undefined,
    cursor_motion: wl.wl_listener = .{ .notify = server_cursor_motion },
    cursor_motion_absolute: wl.wl_listener = .{ .notify = server_cursor_motion_absolute },

    cursor_mode: CursorMode = .CURSOR_PASSTHROUGH,
    grab_geobox: wl.wlr_box = undefined,
    grab_x: f64 = 0.0,
    grab_y: f64 = 0.0,
    grabbed_toplevel: ?*Toplevel = null,
    keyboards: wl.wl_list = undefined,
    new_input: wl.wl_listener = .{ .notify = server_new_input },
    pointer_focus_change: wl.wl_listener = .{ .notify = seat_pointer_focus_change },
    request_cursor: wl.wl_listener = .{ .notify = server_request_cursor },
    request_set_selection: wl.wl_listener = .{ .notify = server_request_set_selection },
    resize_edges: u32 = 0,
    seat: *wl.wlr_seat = undefined,

    new_output: wl.wl_listener = .{ .notify = server_new_output },
    output_layout: *wl.wlr_output_layout = undefined,
    outputs: wl.wl_list = undefined,
};

const Output = struct {
    destroy: wl.wl_listener,
    events: struct {
        frame: wl.wl_signal,
        request_state: wl.wl_listener,
        destroy: wl.wl_listener,
    },
    frame: wl.wl_listener,
    link: wl.wl_list,
    request_state: wl.wl_listener,
    server: *Server,
    wlr_output: *wl.wlr_output,
};

const Toplevel = struct {
    commit: wl.wl_listener,
    destroy: wl.wl_listener,
    link: wl.wl_list,
    map: wl.wl_listener,
    request_fullscreen: wl.wl_listener,
    request_maximize: wl.wl_listener,
    request_move: wl.wl_listener,
    request_resize: wl.wl_listener,
    scene_tree: *wl.wlr_scene_tree,
    server: *Server,
    unmap: wl.wl_listener,
    xdg_toplevel: *wl.wlr_xdg_toplevel,
};

const Popup = struct {
    commit: wl.wl_listener,
    destroy: wl.wl_listener,
    xdg_popup: *wl.wlr_xdg_popup,
};

const Keyboard = struct {
    destroy: wl.wl_listener,
    key: wl.wl_listener,
    key_repeat: wl.wl_listener,
    link: wl.wl_list,
    modifiers: wl.wl_listener,
    server: *Server,
    wlr_keyboard: *wl.wlr_keyboard,
};

pub fn init(p_init: std.process.Init) !Server {
    var server = Server{
        .wl_display = wl.wl_display_create(),
    };
    defer wl.wl_display_destroy(server.wl_display);
    server.backend = wl.wlr_backend_autocreate(
        wl.wl_display_get_event_loop(server.wl_display),
        &server.session,
    );
    defer wl.wlr_backend_destroy(server.backend);
    if (server.backend == null) {
        std.log.err("failed to create wlr_backend", .{});
        return error.BackendCreation;
    }
    server.renderer = wl.wlr_renderer_autocreate(server.backend);
    defer wl.wlr_renderer_destroy(server.renderer);
    if (server.renderer == null) {
        std.log.err("failed to create wlr_renderer", .{});
        return error.RendererCreation;
    }
    _ = wl.wlr_renderer_init_wl_display(
        server.renderer,
        server.wl_display,
    );
    server.allocator = wl.wlr_allocator_autocreate(
        server.backend,
        server.renderer,
    );
    defer wl.wlr_allocator_destroy(server.allocator);
    if (server.allocator == null) {
        std.log.err("failed to create wlr_allocator", .{});
        return error.AllocatorCreation;
    }
    _ = wl.wlr_compositor_create(server.wl_display, 5, server.renderer);
    _ = wl.wlr_subcompositor_create(server.wl_display);
    _ = wl.wlr_data_device_manager_create(server.wl_display);
    server.output_layout = wl.wlr_output_layout_create(server.wl_display);
    wl.wl_list_init(&server.outputs);
    wl.wl_signal_add(
        &server.backend.?.events.new_output,
        &server.new_output,
    );
    defer wl.wl_list_remove(&server.new_output.link);
    server.scene = wl.wlr_scene_create();
    server.scene_layout = wl.wlr_scene_attach_output_layout(
        server.scene,
        server.output_layout,
    );
    wl.wl_list_init(&server.toplevels);
    server.xdg_shell = wl.wlr_xdg_shell_create(
        server.wl_display,
        3,
    );
    wl.wl_signal_add(
        &server.xdg_shell.events.new_toplevel,
        &server.new_xdg_toplevel,
    );
    defer wl.wl_list_remove(&server.new_xdg_toplevel.link);
    wl.wl_signal_add(
        &server.xdg_shell.events.new_popup,
        &server.new_xdg_popup,
    );
    defer wl.wl_list_remove(&server.new_xdg_popup.link);
    server.cursor = wl.wlr_cursor_create();
    defer wl.wlr_cursor_destroy(server.cursor);
    wl.wlr_cursor_attach_output_layout(
        server.cursor,
        server.output_layout,
    );
    server.cursor_mgr = wl.wlr_xcursor_manager_create(null, 24);
    defer wl.wlr_xcursor_manager_destroy(server.cursor_mgr);
    wl.wl_signal_add(
        &server.cursor.events.motion,
        &server.cursor_motion,
    );
    defer wl.wl_list_remove(&server.cursor_motion.link);
    wl.wl_signal_add(
        &server.cursor.events.motion_absolute,
        &server.cursor_motion_absolute,
    );
    defer wl.wl_list_remove(&server.cursor_motion_absolute.link);
    wl.wl_signal_add(
        &server.cursor.events.button,
        &server.cursor_button,
    );
    defer wl.wl_list_remove(&server.cursor_button.link);
    wl.wl_signal_add(
        &server.cursor.events.axis,
        &server.cursor_aixs,
    );
    defer wl.wl_list_remove(&server.cursor_aixs.link);
    wl.wl_signal_add(
        &server.cursor.events.frame,
        &server.cursor_frame,
    );
    defer wl.wl_list_remove(&server.cursor_frame.link);
    wl.wl_list_init(&server.keyboards);
    wl.wl_signal_add(
        &server.backend.?.events.new_input,
        &server.new_input,
    );
    defer wl.wl_list_remove(&server.new_input.link);
    server.seat = wl.wlr_seat_create(server.wl_display, "seat0");
    wl.wl_signal_add(
        &server.seat.events.request_set_cursor,
        &server.request_cursor,
    );
    defer wl.wl_list_remove(&server.request_cursor.link);
    wl.wl_signal_add(
        &server.seat.pointer_state.events.focus_change,
        &server.pointer_focus_change,
    );
    defer wl.wl_list_remove(&server.pointer_focus_change.link);
    wl.wl_signal_add(
        &server.seat.events.request_set_selection,
        &server.request_set_selection,
    );
    defer wl.wl_list_remove(&server.request_set_selection.link);
    const socket = wl.wl_display_add_socket_auto(server.wl_display);
    if (socket == null) {
        std.log.err("failed to create wl_display socket", .{});
        return error.SocketCreation;
    }
    if (!wl.wlr_backend_start(server.backend)) {
        std.log.err("failed to start wlr_backend", .{});
        return error.BackendStart;
    }
    p_init.environ_map.put("WAYLAND_DISPLAY", std.mem.span(socket)) catch {
        std.log.err("failed to set WAYLAND_DISPLAY", .{});
        return error.EnvSet;
    };
    const environ = p_init.environ_map.createPosixBlock(p_init.gpa, .{}) catch {
        std.log.err("failed to create posix block", .{});
        return error.PosixBlock;
    };
    defer environ.deinit(p_init.gpa);
    if (std.os.linux.fork() == 0) {
        _ = std.os.linux.execve(
            "/bin/ghostty",
            &.{},
            environ.slice,
        );
    }
    std.log.info(
        "Running Wayland compositor on WAYLAND_DISPLAY={s}",
        .{socket},
    );
    wl.wl_display_run(server.wl_display);
    wl.wl_display_destroy_clients(server.wl_display);
    wl.wlr_scene_node_destroy(&server.scene.tree.node);
    return server;
}

fn begin_interaction(
    toplevel: *Toplevel,
    mode: u32,
    edges: u32,
) callconv(.c) void {
    const mode_enum: CursorMode = @enumFromInt(mode);
    const server = toplevel.server;
    server.grabbed_toplevel = toplevel;
    server.cursor_mode = mode_enum;
    if (mode_enum == .CURSOR_MOVE) {
        server.grab_x = server.cursor.x -
            toplevel.scene_tree.node.x;
        server.grab_y = server.cursor.y -
            toplevel.scene_tree.node.y;
        return;
    }
    const geo_box = &toplevel.xdg_toplevel.base.*.geometry;
    const border_x = (toplevel.scene_tree.node.x - geo_box.*.x) +
        if ((edges & wl.WLR_EDGE_RIGHT) != 0)
            geo_box.*.width
        else
            0;
    const border_y = (toplevel.scene_tree.node.y - geo_box.*.y) +
        if ((edges & wl.WLR_EDGE_BOTTOM) != 0)
            geo_box.*.height
        else
            0;
    server.grab_x = server.cursor.x - border_x;
    server.grab_y = server.cursor.y - border_y;
    server.grab_geobox = geo_box.*;
    server.grab_geobox.x += toplevel.scene_tree.node.x;
    server.grab_geobox.y += toplevel.scene_tree.node.y;
    server.resize_edges = edges;
}

fn desktop_toplevel_at(
    server: *Server,
    lx: f64,
    ly: f64,
    surface: *?*wl.wlr_surface,
    sx: *f64,
    sy: *f64,
) ?*Toplevel {
    const node = wl.wlr_scene_node_at(
        &server.scene.tree.node,
        lx,
        ly,
        sx,
        sy,
    );
    if (node == null or node.*.type != wl.WLR_SCENE_NODE_BUFFER) {
        return null;
    }
    const scene_buffer = wl.wlr_scene_buffer_from_node(node);
    const scene_surface = wl.wlr_scene_surface_try_from_buffer(scene_buffer);
    if (scene_surface == null) {
        return null;
    }
    surface.* = scene_surface.*.surface;
    var tree = node.*.parent;
    while (tree != null and tree.*.node.data == null) {
        tree = tree.*.node.parent;
    }
    return @ptrCast(@alignCast(tree.?.*.node.data));
}

fn focus_toplevel(toplevel: *Toplevel) void {
    const server = toplevel.server;
    const seat = server.seat;
    const prev_surface = seat.keyboard_state.focused_surface;
    const surface = toplevel.xdg_toplevel.base.*.surface;
    if (prev_surface == surface) {
        return;
    }
    if (prev_surface != null) {
        const prev_toplevel = wl.wlr_xdg_toplevel_try_from_wlr_surface(prev_surface);
        if (prev_toplevel != null) {
            _ = wl.wlr_xdg_toplevel_set_activated(prev_toplevel, false);
        }
    }
    wl.wlr_scene_node_raise_to_top(
        &toplevel.scene_tree.node,
    );
    wl.wl_list_remove(&toplevel.link);
    wl.wl_list_insert(
        &server.toplevels,
        &toplevel.link,
    );
    _ = wl.wlr_xdg_toplevel_set_activated(
        toplevel.xdg_toplevel,
        true,
    );
    const keyboard = wl.wlr_seat_get_keyboard(seat);
    if (keyboard != null) {
        wl.wlr_seat_keyboard_notify_enter(
            seat,
            surface,
            @ptrCast(&keyboard.*.keycodes),
            keyboard.*.num_keycodes,
            &keyboard.*.modifiers,
        );
    }
}

fn handled_keybinding(server: *Server, sym: wl.xkb_keysym_t) bool {
    if ((wl.XKB_KEY_XF86Switch_VT_1 <= sym) and (sym <= wl.XKB_KEY_XF86Switch_VT_12)) {
        const session = server.session;
        if (session != null) {
            _ = wl.wlr_session_change_vt(session, sym - wl.XKB_KEY_XF86Switch_VT_1 + 1);
            return true;
        }
    }
    switch (sym) {
        wl.XKB_KEY_Escape => {
            wl.wl_display_terminate(server.wl_display);
        },
        wl.XKB_KEY_F1 => {
            if (!(wl.wl_list_length(&server.toplevels) < 2)) {
                const toplevel: *Toplevel = @fieldParentPtr(
                    "link",
                    @as(*wl.wl_list, @ptrCast(server.toplevels.prev)),
                );
                focus_toplevel(toplevel);
            }
        },
        else => {
            return false;
        },
    }
    return true;
}

fn keyboard_handle_destroy(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("destroy", listener.?);
    wl.wl_list_remove(&keyboard.modifiers.link);
    wl.wl_list_remove(&keyboard.key.link);
    wl.wl_list_remove(&keyboard.destroy.link);
    wl.wl_list_remove(&keyboard.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, keyboard);
}

fn keyboard_handle_key(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("key", listener.?);
    const server = keyboard.server;
    const event: *wl.wlr_keyboard_key_event = @ptrCast(@alignCast(data));
    const keycode = event.keycode + 8;
    var syms: *wl.xkb_keysym_t = undefined;
    const nsyms = wl.xkb_state_key_get_syms(
        keyboard.wlr_keyboard.xkb_state,
        keycode,
        @ptrCast(&syms),
    );
    var handled = false;
    const modifiers = wl.wlr_keyboard_get_modifiers(keyboard.wlr_keyboard);
    if ((modifiers & wl.WLR_MODIFIER_ALT) != 0 and
        event.state == wl.WL_KEYBOARD_KEY_STATE_PRESSED)
    {
        const syms_slice = @as(
            [*]wl.xkb_keysym_t,
            @ptrCast(syms),
        )[0..@intCast(nsyms)];
        for (syms_slice) |sym| {
            handled = handled_keybinding(server, sym);
        }
    }
    if (!handled) {
        const seat = server.seat;
        _ = wl.wlr_seat_set_keyboard(seat, keyboard.wlr_keyboard);
        wl.wlr_seat_keyboard_notify_key(
            seat,
            event.time_msec,
            event.keycode,
            event.state,
        );
    }
}

fn keyboard_handle_modifiers(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("modifiers", listener.?);
    wl.wlr_seat_set_keyboard(keyboard.server.seat, keyboard.wlr_keyboard);
    wl.wlr_seat_keyboard_notify_modifiers(
        keyboard.server.seat,
        &keyboard.wlr_keyboard.modifiers,
    );
}

fn output_destroy(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("destroy", listener.?);
    wl.wl_list_remove(&output.frame.link);
    wl.wl_list_remove(&output.request_state.link);
    wl.wl_list_remove(&output.destroy.link);
    wl.wl_list_remove(&output.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, output);
}

fn output_frame(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("frame", listener.?);
    const scene = output.server.scene;
    const scene_output: *wl.wlr_scene_output = wl.wlr_scene_get_scene_output(
        scene,
        output.wlr_output,
    );
    _ = wl.wlr_scene_output_commit(scene_output, null);
    var now: wl.timespec = undefined;
    _ = wl.clock_gettime(wl.CLOCK_MONOTONIC, &now);
    wl.wlr_scene_output_send_frame_done(scene_output, &now);
}

fn output_request_state(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("request_state", listener.?);
    const event: *wl.wlr_output_event_request_state = @ptrCast(@alignCast(data));
    _ = wl.wlr_output_commit_state(output.wlr_output, event.state);
}

fn process_cursor_motion(server: *Server, time: u32) void {
    switch (server.cursor_mode) {
        .CURSOR_MOVE => {
            wl.wlr_scene_node_set_position(
                &server.grabbed_toplevel.?.scene_tree.node,
                @intFromFloat(server.cursor.x - server.grab_x),
                @intFromFloat(server.cursor.y - server.grab_y),
            );
        },
        .CURSOR_RESIZE => {
            const border_x: c_int = @intFromFloat(server.cursor.x - server.grab_x);
            const border_y: c_int = @intFromFloat(server.cursor.y - server.grab_y);
            var new_left = server.grab_geobox.x;
            var new_right = server.grab_geobox.x + server.grab_geobox.width;
            var new_top = server.grab_geobox.y;
            var new_bottom = server.grab_geobox.y + server.grab_geobox.height;
            if ((server.resize_edges & wl.WLR_EDGE_TOP) != 0) {
                new_top = border_y;
                if (new_bottom <= new_top) {
                    new_top = new_bottom - 1;
                }
            } else if ((server.resize_edges & wl.WLR_EDGE_BOTTOM) != 0) {
                new_bottom = border_y;
                if (new_bottom <= new_top) {
                    new_bottom = new_top + 1;
                }
            }
            if ((server.resize_edges & wl.WLR_EDGE_LEFT) != 0) {
                new_left = border_x;
                if (new_right <= new_left) {
                    new_left = new_right - 1;
                }
            } else if ((server.resize_edges & wl.WLR_EDGE_RIGHT) != 0) {
                new_right = border_x;
                if (new_right <= new_left) {
                    new_right = new_left + 1;
                }
            }
            const toplevel = server.grabbed_toplevel.?;
            const geo_box = &toplevel.xdg_toplevel.base.*.geometry;
            wl.wlr_scene_node_set_position(
                &toplevel.scene_tree.node,
                new_left - geo_box.*.x,
                new_top - geo_box.*.y,
            );
            _ = wl.wlr_xdg_toplevel_set_size(
                toplevel.xdg_toplevel,
                new_right - new_left,
                new_bottom - new_top,
            );
        },
        .CURSOR_PASSTHROUGH => {
            var sx: f64 = 0.0;
            var sy: f64 = 0.0;
            var surface: ?*wl.wlr_surface = null;
            const toplevel: ?*Toplevel = desktop_toplevel_at(
                server,
                server.cursor.x,
                server.cursor.y,
                &surface,
                &sx,
                &sy,
            );
            if (toplevel == null) {
                wl.wlr_cursor_set_xcursor(
                    server.cursor,
                    server.cursor_mgr,
                    "default",
                );
            }
            const seat = server.seat;
            if (surface != null) {
                wl.wlr_seat_pointer_notify_enter(seat, surface, sx, sy);
                wl.wlr_seat_pointer_notify_motion(seat, time, sx, sy);
            } else {
                wl.wlr_seat_pointer_clear_focus(seat);
            }
        },
    }
}

fn reset_cursor_mode(server: *Server) void {
    server.cursor_mode = .CURSOR_PASSTHROUGH;
    server.grabbed_toplevel = null;
}

fn seat_pointer_focus_change(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("pointer_focus_change", listener.?);
    const event: *wl.wlr_seat_pointer_focus_change_event = @ptrCast(@alignCast(data));
    if (event.new_surface == null) {
        wl.wlr_cursor_set_xcursor(
            server.cursor,
            server.cursor_mgr,
            "default",
        );
    }
}

fn server_cursor_axis(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_aixs", listener.?);
    const event: *wl.wlr_pointer_axis_event = @ptrCast(@alignCast(data));
    wl.wlr_seat_pointer_notify_axis(
        server.seat,
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );
}

fn server_cursor_button(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_button", listener.?);
    const event: *wl.wlr_pointer_button_event = @ptrCast(@alignCast(data));
    _ = wl.wlr_seat_pointer_notify_button(
        server.seat,
        event.time_msec,
        event.button,
        event.state,
    );
    if (event.state == wl.WL_POINTER_BUTTON_STATE_RELEASED) {
        reset_cursor_mode(server);
    } else {
        var sx: f64 = 0.0;
        var sy: f64 = 0.0;
        var surface: ?*wl.wlr_surface = undefined;
        const toplevel: ?*Toplevel = desktop_toplevel_at(
            server,
            server.cursor.x,
            server.cursor.y,
            &surface,
            &sx,
            &sy,
        );
        if (toplevel) |tl| {
            focus_toplevel(tl);
        }
    }
}

fn server_cursor_frame(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_frame", listener.?);
    wl.wlr_seat_pointer_notify_frame(server.seat);
}

fn server_cursor_motion(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion", listener.?);
    const event: *wl.wlr_pointer_motion_event = @ptrCast(@alignCast(data));
    wl.wlr_cursor_move(
        server.cursor,
        &event.pointer.*.base,
        event.delta_x,
        event.delta_y,
    );
    process_cursor_motion(server, event.time_msec);
}

fn server_cursor_motion_absolute(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion_absolute", listener.?);
    const event: *wl.wlr_pointer_motion_absolute_event = @ptrCast(@alignCast(data));
    wl.wlr_cursor_warp_absolute(
        server.cursor,
        &event.pointer.*.base,
        event.x,
        event.y,
    );
    process_cursor_motion(server, event.time_msec);
}

fn server_new_input(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_input", listener.?);
    const device: *wl.wlr_input_device = @ptrCast(@alignCast(data));
    switch (device.type) {
        wl.WLR_INPUT_DEVICE_KEYBOARD => {
            const wlr_keyboard = wl.wlr_keyboard_from_input_device(device);
            var keyboard = std.mem.Allocator.create(
                std.heap.c_allocator,
                Keyboard,
            ) catch unreachable;
            keyboard.server = server;
            keyboard.wlr_keyboard = wlr_keyboard;
            const context = wl.xkb_context_new(wl.XKB_CONTEXT_NO_FLAGS);
            defer wl.xkb_context_unref(context);
            const keymap = wl.xkb_keymap_new_from_names(
                context,
                null,
                wl.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );
            defer wl.xkb_keymap_unref(keymap);
            _ = wl.wlr_keyboard_set_keymap(wlr_keyboard, keymap);
            wl.wlr_keyboard_set_repeat_info(wlr_keyboard, 25, 600);
            keyboard.modifiers.notify = keyboard_handle_modifiers;
            wl.wl_signal_add(
                &wlr_keyboard.*.events.modifiers,
                &keyboard.modifiers,
            );
            keyboard.key.notify = keyboard_handle_key;
            wl.wl_signal_add(
                &wlr_keyboard.*.events.key,
                &keyboard.key,
            );
            keyboard.destroy.notify = keyboard_handle_destroy;
            wl.wl_signal_add(
                &device.events.destroy,
                &keyboard.destroy,
            );
            wl.wlr_seat_set_keyboard(
                server.seat,
                keyboard.wlr_keyboard,
            );
            wl.wl_list_insert(
                &server.keyboards,
                &keyboard.link,
            );
        },
        wl.WLR_INPUT_DEVICE_POINTER => {
            wl.wlr_cursor_attach_input_device(
                server.cursor,
                device,
            );
        },
        else => {},
    }
    var caps = wl.WL_SEAT_CAPABILITY_POINTER;
    if (wl.wl_list_empty(&server.keyboards) == 0) {
        caps |= wl.WL_SEAT_CAPABILITY_KEYBOARD;
    }
    wl.wlr_seat_set_capabilities(server.seat, @intCast(caps));
}

fn server_new_output(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_output: *wl.wlr_output = @ptrCast(@alignCast(data));
    _ = wl.wlr_output_init_render(
        wlr_output,
        server.allocator,
        server.renderer,
    );
    var state: wl.wlr_output_state = undefined;
    wl.wlr_output_state_init(&state);
    wl.wlr_output_state_set_enabled(&state, true);
    const mode = wl.wlr_output_preferred_mode(wlr_output);
    if (mode != null) {
        wl.wlr_output_state_set_mode(&state, mode);
    }
    _ = wl.wlr_output_commit_state(wlr_output, &state);
    wl.wlr_output_state_finish(&state);
    var output: *Output = std.mem.Allocator.create(
        std.heap.c_allocator,
        Output,
    ) catch unreachable;
    output.server = server;
    output.wlr_output = wlr_output;
    output.frame.notify = output_frame;
    wl.wl_signal_add(&wlr_output.events.frame, &output.frame);
    output.request_state.notify = output_request_state;
    wl.wl_signal_add(
        &wlr_output.events.request_state,
        &output.request_state,
    );
    output.destroy.notify = output_destroy;
    wl.wl_signal_add(&wlr_output.events.destroy, &output.destroy);
    wl.wl_list_insert(&server.outputs, &output.link);
    const l_output = wl.wlr_output_layout_add_auto(
        server.output_layout,
        wlr_output,
    );
    const scene_output = wl.wlr_scene_output_create(
        server.scene,
        wlr_output,
    );
    wl.wlr_scene_output_layout_add_output(
        server.scene_layout,
        l_output,
        scene_output,
    );
}

fn server_new_xdg_popup(
    _: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const xdg_popup: *wl.wlr_xdg_popup = @ptrCast(@alignCast(data));
    var popup = std.mem.Allocator.create(
        std.heap.c_allocator,
        Popup,
    ) catch unreachable;
    popup.xdg_popup = xdg_popup;
    const parent = wl.wlr_xdg_surface_try_from_wlr_surface(
        xdg_popup.parent,
    );
    if (parent == null) {
        return;
    }
    xdg_popup.base.*.data = wl.wlr_scene_xdg_surface_create(
        @ptrCast(@alignCast(parent.*.data)),
        xdg_popup.base,
    );
    popup.commit.notify = xdg_popup_commit;
    wl.wl_signal_add(
        &xdg_popup.base.*.surface.*.events.commit,
        &popup.commit,
    );
    popup.destroy.notify = xdg_popup_destroy;
    wl.wl_signal_add(
        &xdg_popup.events.destroy,
        &popup.destroy,
    );
}

fn server_new_xdg_toplevel(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_xdg_toplevel", listener.?);
    const xdg_toplevel: *wl.wlr_xdg_toplevel = @ptrCast(@alignCast(data));
    var toplevel = std.mem.Allocator.create(
        std.heap.c_allocator,
        Toplevel,
    ) catch unreachable;
    toplevel.server = server;
    toplevel.xdg_toplevel = xdg_toplevel;
    toplevel.scene_tree = wl.wlr_scene_xdg_surface_create(
        &toplevel.server.scene.tree,
        xdg_toplevel.base,
    );
    toplevel.*.scene_tree.node.data = toplevel;
    xdg_toplevel.base.*.data = toplevel.scene_tree;
    toplevel.map.notify = xdg_toplevel_map;
    wl.wl_signal_add(
        &xdg_toplevel.base.*.surface.*.events.map,
        &toplevel.map,
    );
    toplevel.unmap.notify = xdg_toplevel_unmap;
    wl.wl_signal_add(
        &xdg_toplevel.base.*.surface.*.events.unmap,
        &toplevel.unmap,
    );
    toplevel.commit.notify = xdg_toplevel_commit;
    wl.wl_signal_add(
        &xdg_toplevel.base.*.surface.*.events.commit,
        &toplevel.commit,
    );
    toplevel.destroy.notify = xdg_toplevel_destroy;
    wl.wl_signal_add(
        &xdg_toplevel.events.destroy,
        &toplevel.destroy,
    );
    toplevel.request_move.notify = xdg_toplevel_request_move;
    wl.wl_signal_add(
        &xdg_toplevel.events.request_move,
        &toplevel.request_move,
    );
    toplevel.request_resize.notify = xdg_toplevel_request_resize;
    wl.wl_signal_add(
        &xdg_toplevel.events.request_resize,
        &toplevel.request_resize,
    );
    toplevel.request_maximize.notify = xdg_toplevel_request_maximize;
    wl.wl_signal_add(
        &xdg_toplevel.events.request_maximize,
        &toplevel.request_maximize,
    );
    toplevel.request_fullscreen.notify = xdg_toplevel_request_fullscreen;
    wl.wl_signal_add(
        &xdg_toplevel.events.request_fullscreen,
        &toplevel.request_fullscreen,
    );
}

fn server_request_cursor(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_cursor", listener.?);
    const event: *wl.wlr_seat_pointer_request_set_cursor_event = @ptrCast(@alignCast(data));
    const focused_event = server.seat.pointer_state.focused_client;
    if (focused_event == event.seat_client) {
        wl.wlr_cursor_set_surface(
            server.cursor,
            event.surface,
            event.hotspot_x,
            event.hotspot_y,
        );
    }
}

fn server_request_set_selection(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_set_selection", listener.?);
    const event: *wl.wlr_seat_request_set_selection_event = @ptrCast(@alignCast(data));
    wl.wlr_seat_set_selection(server.seat, event.source, event.serial);
}

fn xdg_popup_commit(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const popup: *Popup = @fieldParentPtr("commit", listener.?);
    if (popup.xdg_popup.base.*.initial_commit) {
        _ = wl.wlr_xdg_surface_schedule_configure(
            popup.xdg_popup.base,
        );
    }
}

fn xdg_popup_destroy(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const popup: *Popup = @fieldParentPtr("destroy", listener.?);
    wl.wl_list_remove(&popup.commit.link);
    wl.wl_list_remove(&popup.destroy.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, popup);
}

fn xdg_toplevel_commit(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("commit", listener.?);
    if (toplevel.xdg_toplevel.base.*.initial_commit) {
        _ = wl.wlr_xdg_toplevel_set_size(
            toplevel.xdg_toplevel,
            0,
            0,
        );
    }
}

fn xdg_toplevel_destroy(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("destroy", listener.?);
    wl.wl_list_remove(&toplevel.map.link);
    wl.wl_list_remove(&toplevel.unmap.link);
    wl.wl_list_remove(&toplevel.commit.link);
    wl.wl_list_remove(&toplevel.destroy.link);
    wl.wl_list_remove(&toplevel.request_move.link);
    wl.wl_list_remove(&toplevel.request_resize.link);
    wl.wl_list_remove(&toplevel.request_maximize.link);
    wl.wl_list_remove(&toplevel.request_fullscreen.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, toplevel);
}

fn xdg_toplevel_map(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("map", listener.?);
    wl.wl_list_insert(
        &toplevel.server.toplevels,
        &toplevel.link,
    );
    focus_toplevel(toplevel);
}

fn xdg_toplevel_request_fullscreen(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("request_fullscreen", listener.?);
    if (toplevel.xdg_toplevel.base.*.initialized) {
        _ = wl.wlr_xdg_surface_schedule_configure(
            toplevel.xdg_toplevel.base,
        );
    }
}

fn xdg_toplevel_request_maximize(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("request_maximize", listener.?);
    if (toplevel.xdg_toplevel.base.*.initialized) {
        _ = wl.wlr_xdg_surface_schedule_configure(
            toplevel.xdg_toplevel.base,
        );
    }
}

fn xdg_toplevel_request_move(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("request_move", listener.?);
    begin_interaction(
        toplevel,
        @intFromEnum(CursorMode.CURSOR_MOVE),
        0,
    );
}

fn xdg_toplevel_request_resize(
    listener: ?*wl.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("request_resize", listener.?);
    const event: *wl.wlr_xdg_toplevel_resize_event = @ptrCast(@alignCast(data));
    begin_interaction(
        toplevel,
        @intFromEnum(CursorMode.CURSOR_RESIZE),
        event.edges,
    );
}

fn xdg_toplevel_unmap(
    listener: ?*wl.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: *Toplevel = @fieldParentPtr("unmap", listener.?);
    if (toplevel == toplevel.server.grabbed_toplevel) {
        reset_cursor_mode(toplevel.server);
    }
    wl.wl_list_remove(&toplevel.link);
}
