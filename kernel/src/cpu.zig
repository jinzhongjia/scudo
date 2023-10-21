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

    /// get max physical address
    pub inline fn get_max_physical_address() u6 {
        return @truncate(cpuid(0x80000008).eax);
    }

    // NOTE:the MAXPHYADDR which is gaven by bochs and qemu is 40, that's a terrabyt.
    //
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
};

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

const RFLAGS = packed struct(u64) {
    CF: bool = false,
    reserved0: bool = true,
    PF: bool = false,
    reserved1: bool = false,
    AF: bool = false,
    reserved2: bool = false,
    ZF: bool = false,
    SF: bool = false,
    TF: bool = false,
    IF: bool = false,
    DF: bool = false,
    OF: bool = false,
    IOPL: u2 = 0,
    NT: bool = false,
    reserved3: bool = false,
    RF: bool = false,
    VM: bool = false,
    AC: bool = false,
    VIF: bool = false,
    VIP: bool = false,
    ID: bool = false,
    reserved4: u10 = 0,
    reserved5: u32 = 0,
};

pub inline fn get_flags() RFLAGS {
    return asm volatile (
        \\ pushfq
        \\ pop %[flags]
        : [flags] "=r" (-> RFLAGS),
        :
        : "memory"
    );
}

pub inline fn get_interrupt_state() bool {
    return get_flags().IF;
}

/// Clear the IF FLAG and return the previous value
pub inline fn interrupt_disable() bool {
    var tmp: usize = undefined;
    asm volatile (
        \\ pushfq
        \\ cli
        \\ popq %%rax
        \\ shrq $9, %%rax
        \\ andq $1, %%rax
        \\ mov %%rax, %[result]
        : [result] "=r" (tmp),
        :
        : "memory"
    );

    return tmp == 1;
}

pub inline fn stopCPU() noreturn {
    while (true) {
        asm volatile (
            \\cli
            \\hlt
            \\pause
            ::: "memory");
    }
}
