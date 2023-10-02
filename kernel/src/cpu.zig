const limine = @import("limine");
const config = @import("lib.zig").config;

pub export var stack_size_request: limine.StackSizeRequest = .{
    .stack_size = config.stack_size,
};

pub inline fn hlt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
