const limine = @import("limine");
const std = @import("std");

const lib = @import("lib.zig");
const tty = lib.tty;

// 我们内核的入口函数，通过ld连接脚本告诉来了limine,入口在这
export fn _start() callconv(.C) noreturn {

    // 初始化tty的工作
    // TODO: print boot time
    tty.init();
    lib.idt.init();
    lib.clock.init();
    // asm volatile ("xchgw %bx, %bx");
    // asm volatile ("int $0x80");

    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}

var time: u64 = 0;

// 在root作用域定义一个pub panic,覆盖默认的panic
pub const panic = tty.panic;
