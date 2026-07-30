const std = @import("std");
const log = @import("log");

pub fn logger(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    var buf: [64]u8 = undefined;
    if (@import("builtin").mode == .Debug) {
        const io = std.Options.debug_io;
        const prev = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(prev);
        const stderr = std.debug.lockStderr(&buf).terminal();
        defer std.debug.unlockStderr();
        std.log.defaultLogFileTerminal(level, scope, format, args, stderr) catch {};
    }
    const msg = std.fmt.bufPrintZ(
        &buf,
        format,
        args
    ) catch return;
    log.syslog(switch (level) {
        .err => log.LOG_ERR,
        .warn => log.LOG_WARNING,
        .info => log.LOG_INFO,
        .debug => log.LOG_DEBUG,
    }, "%s", msg.ptr);
}
