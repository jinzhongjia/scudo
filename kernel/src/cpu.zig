const limine = @import("limine");
const config = @import("config");

export var stack_size_request: limine.StackSizeRequest = .{
    .stack_size = config.stack_size,
};

export var smp_request: limine.SmpRequest = .{};

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

pub inline fn rbp() usize {
    return asm volatile ("mov %%rbp, %[result]"
        : [result] "=r" (-> usize),
    );
}

// before use this, we need to call check function
pub const CPUID = extern struct {
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
            \\ cpuid
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

    pub inline fn check_available() bool {
        var res: usize = asm volatile (
            \\ pushfq
            \\ pushfq
            \\ xorq $0x200000, (%%rsp)
            \\ popfq
            \\ pushfq
            \\ pop %%rax
            \\ xorq (%%rsp), %%rax
            \\ popfq
            \\ andq $0x200000, %%rax
            \\ mov %%rax, %[result]
            : [result] "=r" (-> usize),
            :
            : "memory", "rsp"
        );
        return res != 0;
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

pub inline fn check_apic() bool {
    var res = CPUID.cpuid(1);
    return res.edx & 0x100 != 0;
}

pub inline fn read_MSR(msr: u32) void {
    var low: u32 = undefined;
    var high: u32 = undefined;

    asm volatile ("rdmsr"
        : [_] "={eax}" (low),
          [_] "={edx}" (high),
        : [_] "{ecx}" (msr),
    );
    return (@as(u64, high) << 32) | low;
}

pub inline fn write_MSR(msr: u32, value: u64) void {
    const low = @as(u32, @truncate(value));
    const high = @as(u32, @truncate(value >> 32));

    asm volatile ("wrmsr"
        :
        : [_] "{eax}" (low),
          [_] "{edx}" (high),
          [_] "{ecx}" (msr),
    );
}

pub const MSR = struct {
    pub fn is_avaiable() bool {
        var res = CPUID.cpuid(1);
        return res.edx & 0x10 != 0;
    }

    pub fn init(comptime msr: u32) type {
        return struct {
            pub inline fn read() u64 {
                var low: u32 = undefined;
                var high: u32 = undefined;

                asm volatile ("rdmsr"
                    : [_] "={eax}" (low),
                      [_] "={edx}" (high),
                    : [_] "{ecx}" (msr),
                );
                return (@as(u64, high) << 32) | low;
            }

            pub inline fn write(value: u64) void {
                const low = @as(u32, @truncate(value));
                const high = @as(u32, @truncate(value >> 32));

                asm volatile ("wrmsr"
                    :
                    : [_] "{eax}" (low),
                      [_] "{edx}" (high),
                      [_] "{ecx}" (msr),
                );
            }
        };
    }
};

pub const IA32_APIC_BASE = packed struct(u64) {
    reserved0: u8 = 0,
    bsp: bool = false,
    ign: bool = false,
    extended: bool = false,
    global_enable: bool = false,
    address: u24,
    reserved2: u28 = 0,

    pub const msr = MSR.init(0x0000001B);

    pub inline fn read() IA32_APIC_BASE {
        const result = msr.read();
        const typed_result = @as(IA32_APIC_BASE, @bitCast(result));
        return typed_result;
    }

    pub inline fn write(typed_value: IA32_APIC_BASE) void {
        const value = @as(u64, @bitCast(typed_value));
        msr.write(value);
    }

    pub inline fn getAddress(ia32_apic_base: IA32_APIC_BASE) usize {
        return @as(usize, ia32_apic_base.address) << @bitOffsetOf(IA32_APIC_BASE, "address");
    }
};

/// Unfortunately, QEMU does not emulate x2apic.
/// You have to use KVM (or a different emulator).
/// You might not need to switch to a physical machine.
/// Some VMs support nested virtualization, which would allow you to use KVM inside your VM
pub fn x2APIC_available() bool {
    return CPUID.cpuid(1).ecx & 0x100000 != 0;
}

pub fn get_cpu_count() usize {
    if (smp_request.response) |response| {
        return @as(usize, response.cpu_count);
    }
    @panic("faild to get smp_request");
}
