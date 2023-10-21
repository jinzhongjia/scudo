const std = @import("std");
pub const log = struct {
    pub const scoped = std.log.scoped;

    err: std.log.err,
    info: std.log.info,
    warn: std.log.warn,
    debug: std.log.debug,
};
pub const stdlib = @import("lib/stdlib.zig");
pub const tty = @import("lib/tty.zig");
pub const boot_info = @import("lib/boot_info.zig");
pub const config = @import("lib/config.zig");
pub const idt = @import("lib/idt.zig");
pub const task = @import("lib/task.zig");
pub const clock = @import("lib/clock.zig");
pub const sound = @import("lib/sound.zig");
pub const time = @import("lib/time.zig");
pub const mem = @import("lib/mem.zig");

pub fn assert(src: std.builtin.SourceLocation, val: bool) void {
    if (!val) tty.panicf(
        "Assert failed at {s}:{}:{} {s}()\n",
        .{
            src.file,
            src.line,
            src.column,
            src.fn_name,
        },
    );
}
