const limine = @import("limine");
const std = @import("std");

const lib = @import("lib.zig");
const tty = lib.tty;
const framebuffer = tty.framebuffer;


// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    tty.init();
    tty.print("{s}", .{"Hello,world!"});

    @panic("We're done, just hang...");
}

// 在root作用域定义一个pub panic,覆盖默认的panic
pub const panic = tty.panic;
