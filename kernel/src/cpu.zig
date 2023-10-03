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

pub inline fn lidt(idtr: usize) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (idtr),
    );
}

pub inline fn sti() void {
    asm volatile ("sti");
}

////
// Read a byte from a port.
//
// Arguments:
//     port: Port from where to read.
//
// Returns:
//     The read byte.
//
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

////
// Write a byte on a port.
//
// Arguments:
//     port: Port where to write the value.
//     value: Value to be written.
//
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}
