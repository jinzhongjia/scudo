const limine = @import("limine");
const config = @import("lib.zig").config;

export var stack_size_request: limine.StackSizeRequest = .{
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

/// Read a byte from a port.
///
/// Arguments:
///     port: Port from where to read.
///
/// Returns:
///     The read byte.
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

/// Write a byte on a port.
///
/// Arguments:
///     port: Port where to write the value.
///     value: Value to be written.
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

/// just for debug
pub inline fn debug() void {
    asm volatile ("xchgw %bx, %bx");
}

/// Invalidate the TLB entry associated with the given virtual address.
///
/// Arguments:
///     v_addr: Virtual address to invalidate.
pub inline fn invlpg(v_addr: usize) void {
    asm volatile ("invlpg (%[v_addr])"
        :
        : [v_addr] "r" (v_addr),
        : "memory"
    );
}

const CPUID = extern struct {
    eax: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
};

// NOTE:the MAXPHYADDR which is gaven by bochs and qemu is 40, that's a terrabyt.
//maybe we need more to write to the address

pub inline fn cpuid(leaf: u32) CPUID {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var edx: u32 = undefined;
    var ecx: u32 = undefined;

    asm volatile (
        \\cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [edx] "={edx}" (edx),
          [ecx] "={ecx}" (ecx),
        : [leaf] "{eax}" (leaf),
    );

    return CPUID{
        .eax = eax,
        .ebx = ebx,
        .edx = edx,
        .ecx = ecx,
    };
}

/// read cr2 register
pub inline fn readCR2() usize {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> usize),
    );
}

/// write to cr3 register
pub inline fn writeCR3(pd: usize) void {
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (pd),
    );
}

/// read cr2 register
pub inline fn readCR3() usize {
    return asm volatile ("mov %%cr3, %[result]"
        : [result] "=r" (-> usize),
    );
}

pub inline fn get_PML4() usize {
    return readCR3() & 0xfffffffffffff000;
}
