const c = @import("c");
const std = @import("std");

const CursorMode = enum {
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

    cursor_mode: CursorMode = .CURSOR_PASSTHROUGH,
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
    commit: c.wl_listener,
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

pub fn init(p_init: std.process.Init) !Server {
    var server = Server{
        .wl_display = c.wl_display_create(),
    };
    server.backend = c.wlr_backend_autocreate(
        c.wl_display_get_event_loop(server.wl_display),
        null,
    );
    if (server.backend == null) {
        std.log.err("failed to create wlr_backend", .{});
        return error.BackendCreation;
    }
    server.renderer = c.wlr_renderer_autocreate(server.backend);
    if (server.renderer == null) {
        std.log.err("failed to create wlr_renderer", .{});
        return error.RendererCreation;
    }
    _ = c.wlr_renderer_init_wl_display(
        server.renderer,
        server.wl_display,
    );
    server.allocator = c.wlr_allocator_autocreate(
        server.backend,
        server.renderer,
    );
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
    c.wl_signal_add(
        &server.backend.?.events.new_output,
        &server.new_output,
    );
    server.scene = c.wlr_scene_create();
    server.scene_layout = c.wlr_scene_attach_output_layout(
        server.scene,
        server.output_layout,
    );
    c.wl_list_init(&server.toplevels);
    server.xdg_shell = c.wlr_xdg_shell_create(
        server.wl_display,
        3,
    );
    server.new_xdg_toplevel.notify = server_new_xdg_toplevel;
    c.wl_signal_add(
        &server.xdg_shell.?.events.new_toplevel,
        &server.new_xdg_toplevel,
    );
    server.new_xdg_popup.notify = server_new_xdg_popup;
    c.wl_signal_add(
        &server.xdg_shell.?.events.new_popup,
        &server.new_xdg_popup,
    );
    server.cursor = c.wlr_cursor_create();
    c.wlr_cursor_attach_output_layout(
        server.cursor,
        server.output_layout,
    );
    server.cursor_mgr = c.wlr_xcursor_manager_create(null, 24);
    server.cursor_motion.notify = server_cursor_motion;
    c.wl_signal_add(
        &server.cursor.?.events.motion,
        &server.cursor_motion,
    );
    server.cursor_motion_absolute.notify = server_cursor_motion_absolute;
    c.wl_signal_add(
        &server.cursor.?.events.motion_absolute,
        &server.cursor_motion_absolute,
    );
    server.cursor_button.notify = server_cursor_button;
    c.wl_signal_add(
        &server.cursor.?.events.button,
        &server.cursor_button,
    );
    server.cursor_aixs.notify = server_cursor_axis;
    c.wl_signal_add(
        &server.cursor.?.events.axis,
        &server.cursor_aixs,
    );
    server.cursor_frame.notify = server_cursor_frame;
    c.wl_signal_add(
        &server.cursor.?.events.frame,
        &server.cursor_frame,
    );
    c.wl_list_init(&server.keyboards);
    server.new_input.notify = server_new_input;
    c.wl_signal_add(
        &server.backend.?.events.new_input,
        &server.new_input,
    );
    server.seat = c.wlr_seat_create(server.wl_display, "seat0");
    server.request_cursor.notify = server_request_cursor;
    c.wl_signal_add(
        &server.seat.?.events.request_set_cursor,
        &server.request_cursor,
    );
    server.request_set_selection.notify = server_request_set_selection;
    c.wl_signal_add(
        &server.seat.?.events.request_set_selection,
        &server.request_set_selection,
    );
    const socket = c.wl_display_add_socket_auto(server.wl_display);
    if (socket == null) {
        c.wlr_backend_destroy(server.backend);
        std.log.err("failed to create wl_display socket", .{});
        return error.SocketCreation;
    }
    if (!c.wlr_backend_start(server.backend)) {
        c.wlr_backend_destroy(server.backend);
        c.wl_display_destroy(server.wl_display);
        std.log.err("failed to start wlr_backend", .{});
        return error.BackendStart;
    }
    p_init.environ_map.put("WAYLAND_DISPLAY", std.mem.span(socket)) catch {
        c.wlr_backend_destroy(server.backend);
        c.wl_display_destroy(server.wl_display);
        std.log.err("failed to set WAYLAND_DISPLAY", .{});
        return error.EnvSet;
    };
    if (std.os.linux.fork() == 0) {
        _ = std.os.linux.execve(
            "/bin/ghostty",
            &.{},
            std.mem.span(std.c.environ),
        );
    }
    std.log.info(
        "Running Wayland compositor on WAYLAND_DISPLAY={s}",
        .{socket},
    );
    c.wl_display_run(server.wl_display);
    c.wl_display_destroy_clients(server.wl_display);
    c.wl_list_remove(&server.new_xdg_toplevel.link);
    c.wl_list_remove(&server.new_xdg_popup.link);
    c.wl_list_remove(&server.cursor_motion.link);
    c.wl_list_remove(&server.cursor_motion_absolute.link);
    c.wl_list_remove(&server.cursor_button.link);
    c.wl_list_remove(&server.cursor_aixs.link);
    c.wl_list_remove(&server.cursor_frame.link);
    c.wl_list_remove(&server.new_input.link);
    c.wl_list_remove(&server.request_cursor.link);
    c.wl_list_remove(&server.pointer_focus_change.link);
    c.wl_list_remove(&server.request_set_selection.link);
    c.wl_list_remove(&server.new_output.link);
    c.wlr_scene_node_destroy(&server.scene.?.tree.node);
    c.wlr_xcursor_manager_destroy(server.cursor_mgr);
    c.wlr_cursor_destroy(server.cursor);
    c.wlr_allocator_destroy(server.allocator);
    c.wlr_renderer_destroy(server.renderer);
    c.wlr_backend_destroy(server.backend);
    c.wl_display_destroy(server.wl_display);
    return server;
}

fn begin_interaction(
    toplevel: ?*Toplevel,
    mode: u32,
    edges: u32,
) callconv(.c) void {
    const mode_enum: CursorMode = @enumFromInt(mode);
    const server = toplevel.?.server;
    server.?.grabbed_toplevel = toplevel;
    server.?.cursor_mode = mode_enum;
    if (mode_enum == .CURSOR_MOVE) {
        server.?.grab_x = server.?.cursor.?.x -
            toplevel.?.scene_tree.?.node.x;
        server.?.grab_y = server.?.cursor.?.y -
            toplevel.?.scene_tree.?.node.y;
        return;
    }
    const geo_box = &toplevel.?.xdg_toplevel.?.base.*.geometry;
    const border_x = (toplevel.?.scene_tree.?.node.x - geo_box.*.x) +
        if (edges & c.WLR_EDGE_RIGHT == 1)
            geo_box.*.width
        else
            0;
    const border_y = (toplevel.?.scene_tree.?.node.y - geo_box.*.y) +
        if (edges & c.WLR_EDGE_BOTTOM == 1)
            geo_box.*.height
        else
            0;
    server.?.grab_x = server.?.cursor.?.x - border_x;
    server.?.grab_y = server.?.cursor.?.y - border_y;
    server.?.grab_geobox = geo_box.*;
    server.?.grab_geobox.x += toplevel.?.scene_tree.?.node.x;
    server.?.grab_geobox.y += toplevel.?.scene_tree.?.node.y;
    server.?.resize_edges = edges;
}

fn desktop_toplevel_at(
    server: ?*Server,
    lx: f64,
    ly: f64,
    surface: *?*c.wlr_surface,
    sx: *f64,
    sy: *f64,
) ?*Toplevel {
    const node = c.wlr_scene_node_at(
        &server.?.scene.?.tree.node,
        lx,
        ly,
        sx,
        sy,
    );
    if (node == null or node.*.type != c.WLR_SCENE_NODE_BUFFER) {
        return null;
    }
    const scene_buffer = c.wlr_scene_buffer_from_node(node);
    const scene_surface = c.wlr_scene_surface_try_from_buffer(scene_buffer);
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
    c.wlr_scene_node_raise_to_top(
        &toplevel.?.scene_tree.?.node,
    );
    c.wl_list_remove(&toplevel.?.link);
    c.wl_list_insert(
        &server.?.toplevels,
        &toplevel.?.link,
    );
    _ = c.wlr_xdg_toplevel_set_activated(
        toplevel.?.xdg_toplevel,
        true,
    );
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

fn handled_keybinding(server: ?*Server, sym: c.xkb_keysym_t) bool {
    switch (sym) {
        c.XKB_KEY_Escape => {
            c.wl_display_terminate(server.?.wl_display);
        },
        c.XKB_KEY_F1 => {
            if (!(c.wl_list_length(&server.?.toplevels) < 2)) {
                const toplevel: *Toplevel = @fieldParentPtr(
                    "link",
                    @as(*c.wl_list, @ptrCast(server.?.toplevels.prev)),
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
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&keyboard.modifiers.link);
    c.wl_list_remove(&keyboard.key.link);
    c.wl_list_remove(&keyboard.destroy.link);
    c.wl_list_remove(&keyboard.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, keyboard);
}

fn keyboard_handle_key(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("key", listener.?);
    const server = keyboard.server;
    const event: *c.wlr_keyboard_key_event = @ptrCast(@alignCast(data));
    const keycode = event.keycode + 8;
    var syms: *c.xkb_keysym_t = undefined;
    const nsyms = c.xkb_state_key_get_syms(
        keyboard.wlr_keyboard.?.xkb_state,
        keycode,
        @ptrCast(&syms),
    );
    var handled = false;
    const modifiers = c.wlr_keyboard_get_modifiers(keyboard.wlr_keyboard);
    if (modifiers & c.WLR_MODIFIER_ALT != 0 and
        event.state == c.WL_KEYBOARD_KEY_STATE_PRESSED)
    {
        const syms_slice = @as(
            [*]c.xkb_keysym_t,
            @ptrCast(syms),
        )[0..@intCast(nsyms)];
        for (syms_slice) |sym| {
            handled = handled_keybinding(server, sym);
        }
    }
    if (!handled) {
        const seat = server.?.seat;
        _ = c.wlr_seat_set_keyboard(seat, keyboard.wlr_keyboard);
        c.wlr_seat_keyboard_notify_key(
            seat,
            event.time_msec,
            event.keycode,
            event.state,
        );
    }
}

fn keyboard_handle_modifiers(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const keyboard: *Keyboard = @fieldParentPtr("modifiers", listener.?);
    c.wlr_seat_set_keyboard(keyboard.server.?.seat, keyboard.wlr_keyboard);
    c.wlr_seat_keyboard_notify_modifiers(
        keyboard.server.?.seat,
        &keyboard.wlr_keyboard.?.modifiers,
    );
}

fn output_destroy(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&output.frame.link);
    c.wl_list_remove(&output.request_state.link);
    c.wl_list_remove(&output.destroy.link);
    c.wl_list_remove(&output.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, output);
}

fn output_frame(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("frame", listener.?);
    const scene = output.server.?.scene;
    const scene_output: *c.wlr_scene_output = c.wlr_scene_get_scene_output(
        scene,
        output.wlr_output,
    );
    _ = c.wlr_scene_output_commit(scene_output, null);
    var now: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(scene_output, &now);
}

fn output_request_state(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const output: *Output = @fieldParentPtr("request_state", listener.?);
    const event: *c.wlr_output_event_request_state = @ptrCast(@alignCast(data));
    _ = c.wlr_output_commit_state(output.wlr_output, event.state);
}

fn process_cursor_motion(server: *Server, time: u32) void {
    switch (server.cursor_mode) {
        .CURSOR_MOVE => {
            c.wlr_scene_node_set_position(
                &server.grabbed_toplevel.?.scene_tree.?.node,
                @intFromFloat(server.cursor.?.x - server.grab_x),
                @intFromFloat(server.cursor.?.y - server.grab_y),
            );
        },
        .CURSOR_RESIZE => {
            const border_x: c_int = @intFromFloat(server.cursor.?.x - server.grab_x);
            const border_y: c_int = @intFromFloat(server.cursor.?.y - server.grab_y);
            var new_left = server.grab_geobox.x;
            var new_right = server.grab_geobox.x + server.grab_geobox.width;
            var new_top = server.grab_geobox.y;
            var new_bottom = server.grab_geobox.y + server.grab_geobox.height;
            if (server.resize_edges & c.WLR_EDGE_TOP == 1) {
                new_top = border_y;
                if (new_bottom <= new_top) {
                    new_top = new_bottom - 1;
                }
            } else if (server.resize_edges & c.WLR_EDGE_BOTTOM == 1) {
                new_bottom = border_y;
                if (new_bottom <= new_top) {
                    new_bottom = new_top + 1;
                }
            } else if (server.resize_edges & c.WLR_EDGE_LEFT == 1) {
                new_left = border_x;
                if (new_right <= new_left) {
                    new_left = new_right - 1;
                }
            } else if (server.resize_edges & c.WLR_EDGE_RIGHT == 1) {
                new_right = border_x;
                if (new_right <= new_left) {
                    new_right = new_left + 1;
                }
            }
            const toplevel = server.grabbed_toplevel.?;
            const geo_box = &toplevel.xdg_toplevel.?.base.*.geometry;
            c.wlr_scene_node_set_position(
                &toplevel.scene_tree.?.node,
                new_left - geo_box.*.x,
                new_top - geo_box.*.y,
            );
            _ = c.wlr_xdg_toplevel_set_size(
                toplevel.xdg_toplevel,
                new_right - new_left,
                new_bottom - new_top,
            );
        },
        .CURSOR_PASSTHROUGH => {
            var sx: f64 = 0.0;
            var sy: f64 = 0.0;
            var surface: ?*c.wlr_surface = null;
            const toplevel: ?*Toplevel = desktop_toplevel_at(
                server,
                server.cursor.?.x,
                server.cursor.?.y,
                &surface,
                &sx,
                &sy,
            );
            if (toplevel == null) {
                c.wlr_cursor_set_xcursor(
                    server.cursor,
                    server.cursor_mgr,
                    "default",
                );
            }
            const seat = server.seat;
            if (surface != null) {
                c.wlr_seat_pointer_notify_enter(seat, surface, sx, sy);
                c.wlr_seat_pointer_notify_motion(seat, time, sx, sy);
            } else {
                c.wlr_seat_pointer_clear_focus(seat);
            }
        },
    }
}

fn reset_cursor_mode(server: ?*Server) void {
    server.?.cursor_mode = .CURSOR_PASSTHROUGH;
    server.?.grabbed_toplevel = null;
}

fn server_cursor_axis(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_aixs", listener.?);
    const event: *c.wlr_pointer_axis_event = @ptrCast(@alignCast(data));
    c.wlr_seat_pointer_notify_axis(
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
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_button", listener.?);
    const event: *c.wlr_pointer_button_event = @ptrCast(@alignCast(data));
    _ = c.wlr_seat_pointer_notify_button(
        server.seat,
        event.time_msec,
        event.button,
        event.state,
    );
    if (event.state == c.WL_POINTER_BUTTON_STATE_RELEASED) {
        reset_cursor_mode(server);
    } else {
        var sx: f64 = 0.0;
        var sy: f64 = 0.0;
        var surface: ?*c.wlr_surface = undefined;
        const toplevel: ?*Toplevel = desktop_toplevel_at(
            server,
            server.cursor.?.x,
            server.cursor.?.y,
            &surface,
            &sx,
            &sy,
        );
        focus_toplevel(toplevel);
    }
}

fn server_cursor_frame(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_frame", listener.?);
    c.wlr_seat_pointer_notify_frame(server.seat);
}

fn server_cursor_motion(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion", listener.?);
    const event: *c.wlr_pointer_motion_event = @ptrCast(@alignCast(data));
    c.wlr_cursor_move(
        server.cursor,
        &event.pointer.*.base,
        event.delta_x,
        event.delta_y,
    );
    process_cursor_motion(server, event.time_msec);
}

fn server_cursor_motion_absolute(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion_absolute", listener.?);
    const event: *c.wlr_pointer_motion_absolute_event = @ptrCast(@alignCast(data));
    c.wlr_cursor_warp_absolute(
        server.cursor,
        &event.pointer.*.base,
        event.x,
        event.y,
    );
    process_cursor_motion(server, event.time_msec);
}

fn server_new_input(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_input", listener.?);
    const device: *c.wlr_input_device = @ptrCast(@alignCast(data));
    switch (device.type) {
        c.WLR_INPUT_DEVICE_KEYBOARD => {
            const wlr_keyboard = c.wlr_keyboard_from_input_device(device);
            var keyboard = std.mem.Allocator.create(
                std.heap.c_allocator,
                Keyboard,
            ) catch unreachable;
            keyboard.server = server;
            keyboard.wlr_keyboard = wlr_keyboard;
            const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
            defer c.xkb_context_unref(context);
            const keymap = c.xkb_keymap_new_from_names(
                context,
                null,
                c.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );
            defer c.xkb_keymap_unref(keymap);
            _ = c.wlr_keyboard_set_keymap(wlr_keyboard, keymap);
            c.wlr_keyboard_set_repeat_info(wlr_keyboard, 25, 600);
            keyboard.modifiers.notify = keyboard_handle_modifiers;
            c.wl_signal_add(
                &wlr_keyboard.*.events.modifiers,
                &keyboard.modifiers,
            );
            keyboard.key.notify = keyboard_handle_key;
            c.wl_signal_add(
                &wlr_keyboard.*.events.key,
                &keyboard.key,
            );
            keyboard.destroy.notify = keyboard_handle_destroy;
            c.wl_signal_add(
                &device.events.destroy,
                &keyboard.destroy,
            );
            c.wlr_seat_set_keyboard(
                server.seat,
                keyboard.wlr_keyboard,
            );
            c.wl_list_insert(
                &server.keyboards,
                &keyboard.link,
            );
        },
        c.WLR_INPUT_DEVICE_POINTER => {
            c.wlr_cursor_attach_input_device(
                server.cursor,
                device,
            );
        },
        else => {},
    }
    var caps = c.WL_SEAT_CAPABILITY_POINTER;
    if (c.wl_list_empty(&server.keyboards) == 0) {
        caps |= c.WL_SEAT_CAPABILITY_KEYBOARD;
    }
    c.wlr_seat_set_capabilities(server.seat, @intCast(caps));
}

fn server_new_output(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_output: ?*c.wlr_output = @ptrCast(@alignCast(data));
    _ = c.wlr_output_init_render(
        wlr_output,
        server.allocator,
        server.renderer,
    );
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    c.wlr_output_state_set_enabled(&state, true);
    const mode = c.wlr_output_preferred_mode(wlr_output);
    if (mode != null) {
        c.wlr_output_state_set_mode(&state, mode);
    }
    _ = c.wlr_output_commit_state(wlr_output, &state);
    c.wlr_output_state_finish(&state);
    var output: *Output = std.mem.Allocator.create(
        std.heap.c_allocator,
        Output,
    ) catch unreachable;
    output.server = server;
    output.wlr_output = wlr_output;
    output.frame.notify = output_frame;
    c.wl_signal_add(&wlr_output.?.events.frame, &output.frame);
    output.request_state.notify = output_request_state;
    c.wl_signal_add(
        &wlr_output.?.events.request_state,
        &output.request_state,
    );
    output.destroy.notify = output_destroy;
    c.wl_signal_add(&wlr_output.?.events.destroy, &output.destroy);
    c.wl_list_insert(&server.outputs, &output.link);
    const l_output = c.wlr_output_layout_add_auto(
        server.output_layout,
        wlr_output,
    );
    const scene_output = c.wlr_scene_output_create(
        server.scene,
        wlr_output,
    );
    c.wlr_scene_output_layout_add_output(
        server.scene_layout,
        l_output,
        scene_output,
    );
}

fn server_new_xdg_popup(
    _: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const xdg_popup: ?*c.wlr_xdg_popup = @ptrCast(@alignCast(data));
    var popup = std.mem.Allocator.create(
        std.heap.c_allocator,
        Popup,
    ) catch unreachable;
    popup.xdg_popup = xdg_popup;
    const parent = c.wlr_xdg_surface_try_from_wlr_surface(
        xdg_popup.?.parent,
    );
    if (parent == null) {
        return;
    }
    xdg_popup.?.base.*.data = c.wlr_scene_xdg_surface_create(
        @ptrCast(@alignCast(parent.*.data)),
        xdg_popup.?.base,
    );
    popup.commit.notify = xdg_popup_commit;
    c.wl_signal_add(
        &xdg_popup.?.base.*.surface.*.events.commit,
        &popup.commit,
    );
    popup.destroy.notify = xdg_popup_destroy;
    c.wl_signal_add(
        &xdg_popup.?.events.destroy,
        &popup.destroy,
    );
}

fn server_new_xdg_toplevel(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
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
    c.wl_signal_add(
        &xdg_toplevel.?.base.*.surface.*.events.map,
        &toplevel.map,
    );
    toplevel.unmap.notify = xdg_toplevel_unmap;
    c.wl_signal_add(
        &xdg_toplevel.?.base.*.surface.*.events.unmap,
        &toplevel.unmap,
    );
    toplevel.commit.notify = xdg_toplevel_commit;
    c.wl_signal_add(
        &xdg_toplevel.?.base.*.surface.*.events.commit,
        &toplevel.commit,
    );
    toplevel.destroy.notify = xdg_toplevel_destroy;
    c.wl_signal_add(
        &xdg_toplevel.?.base.*.surface.*.events.destroy,
        &toplevel.destroy,
    );
    toplevel.request_move.notify = xdg_toplevel_request_move;
    c.wl_signal_add(
        &xdg_toplevel.?.events.request_move,
        &toplevel.request_move,
    );
    toplevel.request_resize.notify = xdg_toplevel_request_resize;
    c.wl_signal_add(
        &xdg_toplevel.?.events.request_resize,
        &toplevel.request_resize,
    );
    toplevel.request_maximize.notify = xdg_toplevel_request_maximize;
    c.wl_signal_add(
        &xdg_toplevel.?.events.request_maximize,
        &toplevel.request_maximize,
    );
    toplevel.request_fullscreen.notify = xdg_toplevel_request_fullscreen;
    c.wl_signal_add(
        &xdg_toplevel.?.events.request_fullscreen,
        &toplevel.request_fullscreen,
    );
}

fn server_request_cursor(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_cursor", listener.?);
    const event: *c.wlr_seat_pointer_request_set_cursor_event = @ptrCast(@alignCast(data));
    const focused_event = server.seat.?.pointer_state.focused_client;
    if (focused_event == event.seat_client) {
        c.wlr_cursor_set_surface(
            server.cursor,
            event.surface,
            event.hotspot_x,
            event.hotspot_y,
        );
    }
}

fn server_request_set_selection(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_set_selection", listener.?);
    const event: *c.wlr_seat_request_set_selection_event = @ptrCast(@alignCast(data));
    c.wlr_seat_set_selection(server.seat, event.source, event.serial);
}

fn xdg_popup_commit(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const popup: ?*Popup = @fieldParentPtr("commit", listener.?);
    if (popup.?.xdg_popup.?.base.*.initial_commit) {
        _ = c.wlr_xdg_surface_schedule_configure(
            popup.?.xdg_popup.?.base,
        );
    }
}

fn xdg_popup_destroy(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const popup: ?*Popup = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&popup.?.commit.link);
    c.wl_list_remove(&popup.?.destroy.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, popup.?);
}

fn xdg_toplevel_commit(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("commit", listener.?);
    if (toplevel.?.xdg_toplevel.?.base.*.initial_commit) {
        _ = c.wlr_xdg_toplevel_set_size(
            toplevel.?.xdg_toplevel,
            0,
            0,
        );
    }
}

fn xdg_toplevel_destroy(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&toplevel.?.map.link);
    c.wl_list_remove(&toplevel.?.unmap.link);
    c.wl_list_remove(&toplevel.?.commit.link);
    c.wl_list_remove(&toplevel.?.destroy.link);
    c.wl_list_remove(&toplevel.?.request_move.link);
    c.wl_list_remove(&toplevel.?.request_resize.link);
    c.wl_list_remove(&toplevel.?.request_maximize.link);
    c.wl_list_remove(&toplevel.?.request_fullscreen.link);
    std.mem.Allocator.destroy(std.heap.c_allocator, toplevel.?);
}

fn xdg_toplevel_map(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("map", listener.?);
    c.wl_list_insert(
        &toplevel.?.server.?.toplevels,
        &toplevel.?.link,
    );
    focus_toplevel(toplevel);
}

fn xdg_toplevel_request_fullscreen(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("request_fullscreen", listener.?);
    if (toplevel.?.xdg_toplevel.?.base.*.initialized) {
        _ = c.wlr_xdg_surface_schedule_configure(
            toplevel.?.xdg_toplevel.?.base,
        );
    }
}

fn xdg_toplevel_request_maximize(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("request_maximize", listener.?);
    if (toplevel.?.xdg_toplevel.?.base.*.initialized) {
        _ = c.wlr_xdg_surface_schedule_configure(
            toplevel.?.xdg_toplevel.?.base,
        );
    }
}

fn xdg_toplevel_request_move(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("request_move", listener.?);
    begin_interaction(
        toplevel,
        @intFromEnum(CursorMode.CURSOR_MOVE),
        0,
    );
}

fn xdg_toplevel_request_resize(
    listener: ?*c.wl_listener,
    data: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("request_resize", listener.?);
    const event: *c.wlr_xdg_toplevel_resize_event = @ptrCast(@alignCast(data));
    begin_interaction(
        toplevel,
        @intFromEnum(CursorMode.CURSOR_RESIZE),
        event.edges,
    );
}

fn xdg_toplevel_unmap(
    listener: ?*c.wl_listener,
    _: ?*anyopaque,
) callconv(.c) void {
    const toplevel: ?*Toplevel = @fieldParentPtr("unmap", listener.?);
    if (toplevel == toplevel.?.server.?.grabbed_toplevel) {
        reset_cursor_mode(toplevel.?.server);
    }
    c.wl_list_remove(&toplevel.?.link);
}
