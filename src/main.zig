const wl = @import("wayland");
const server = @import("server.zig");
const std = @import("std");

pub const std_options = std.Options{
    .logFn = @import("log.zig").logger,
};

pub fn main(init: std.process.Init) !void {
    wl.wlr_log_init(if (@import("builtin").mode == .Debug)
        wl.WLR_DEBUG
    else
        wl.WLR_INFO, null);
    _ = try server.init(init);
    _ = init.arena.allocator();
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer = std.Io.File.Writer.init(
        .stdout(),
        io,
        &stdout_buffer,
    );
    _ = &stdout_file_writer.interface;
}
