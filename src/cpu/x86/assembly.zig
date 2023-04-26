////
// Halt the CPU.
//
pub inline fn hlt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

////
// Disable interrupts.
//
pub inline fn cli() void {
    asm volatile ("cli");
}

////
// Enable interrupts.
//
pub inline fn sti() void {
    asm volatile ("sti");
}

////
// Completely stop the computer.
//
pub inline fn hang() noreturn {
    cli();
    hlt();
}

////
// Load a new Interrupt Descriptor Table.
//
// Arguments:
//     idtr: Address of the IDTR register.
//
pub inline fn lidt(idtr: usize) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (idtr),
    );
}

////
// Load a new Task Register.
//
// Arguments:
//     desc: Segment selector of the TSS.
//
pub inline fn ltr(desc: u16) void {
    asm volatile ("ltr %[desc]"
        :
        : [desc] "r" (desc),
    );
}

////
// Invalidate the TLB entry associated with the given virtual address.
//
// Arguments:
//     v_addr: Virtual address to invalidate.
//
pub inline fn invlpg(v_addr: usize) void {
    asm volatile ("invlpg (%[v_addr])"
        :
        : [v_addr] "r" (v_addr),
        : "memory"
    );
}

////
// Read the CR2 control register.
//
pub inline fn readCR2() usize {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> usize),
    );
}

////
// Write the CR3 control register.
//
pub inline fn writeCR3(pd: usize) void {
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (pd),
    );
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
