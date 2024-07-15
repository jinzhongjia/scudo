const lib = @import("lib.zig");

const main = @import("main.zig").main;

export fn _start() callconv(.C) noreturn {
    main();
}

// override default panic
pub const panic = lib.tty.panic;

// for std log

pub const std_options = .{
    .logFn = lib.tty.logFn,
};
