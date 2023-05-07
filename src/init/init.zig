const std = @import("std");
const multiboot_v1 = @import("multiboot").v1;
// const multiboot_v2 = @import("multiboot").v2;
const cpu = @import("cpu");
const assembly = cpu.x86.assembly;

const lib = @import("lib");

const tty = lib.tty;

var tmp: u8 = 5;

export const header_v1 linksection(".multiboot_v1") = multiboot_v1.Header{};

// export const header_v2 linksection(".multiboot_v2") = multiboot_v2.Header{};

export fn init(magic: u32, info: *const multiboot_v1.Info) void {
    lib.tty.initialize();

    if (magic != multiboot_v1.BOOT_MAGIC) {
        lib.tty.panic("multiboot bootloader errors", .{});
    }

    lib.gdt.initialize();

    lib.idt.initialize();

    lib.pmem.initialize(info);

    lib.vmem.initialize();

    lib.mem.initialize(0x10000);

    lib.timer.initialize(100);

    lib.scheduler.initialize();

    assembly.sti();
    assembly.hlt();
}

// Here is define the assembly about start
comptime {
    asm (
        \\ .global _start
        \\ .type _start, @function
        \\ 
        \\ // Entry point. It puts the machine into a consistent state,
        \\ // starts the kernel and then waits forever.
        \\ _start:
        \\     mov $0x80000, %esp  // Setup the stack.
        \\ 
        \\     push %ebx   // Pass multiboot info structure.
        \\     push %eax   // Pass multiboot magic code.
        \\ 
        \\     call init  // Call the kernel.
        \\ 
        \\     // Halt the CPU.
        \\  loop:
        \\      hlt
        \\      jmp loop
    );
}
