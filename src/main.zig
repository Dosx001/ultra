const c = @import("c");
const server = @import("server.zig");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    c.wlr_log_init(if (@import("builtin").mode == .Debug)
        c.WLR_DEBUG
    else
        c.WLR_INFO, null);
    _ = try server.init();
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
