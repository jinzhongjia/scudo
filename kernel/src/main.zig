const limine = @import("limine");
const std = @import("std");

const lib = @import("lib.zig");
const tty = lib.tty;

// 我们内核的入口函数，通过ld连接脚本告诉来了limine,入口在这
export fn _start() callconv(.C) noreturn {

    // 初始化tty的工作
    tty.init();
    tty.println("{s}", .{"Hello World!"});
    var boot_time = lib.boot_info.bootTimeUTC2(lib.boot_info.time_zone.CTorCST);
    tty.println("boot time is {d}.{d}.{d} {d}:{d}:{d}", .{
        boot_time.year,
        boot_time.month,
        boot_time.day,
        boot_time.hour,
        boot_time.minute,
        boot_time.second,
    });

    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}

// 在root作用域定义一个pub panic,覆盖默认的panic
pub const panic = tty.panic;
