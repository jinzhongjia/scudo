const limine = @import("limine");
const idt = @import("idt.zig");
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");

const PAGE_SIZE = 0x1000;

export var limine_mem_map: limine.MemoryMapRequest = .{};
export var limine_HHDM: limine.HhdmRequest = .{};
export var limine_kernel_addr: limine.KernelAddressRequest = .{};

pub fn init() void {
    P_MEM.init();
    V_MEM.init();
    if (limine_kernel_addr.response == null) {
        @panic("can't get kernel_addr response from limine");
    }
}

pub const P_MEM = struct {
    /// this is entries for memory map
    var memmap_entries: []*limine.MemoryMapEntry = undefined;

    var memory_map: []u8 = undefined;

    // page number
    var total_pages: u64 = 0;
    var free_pages: u64 = 0;

    // physical memory array's pages
    var memmap_pages: u64 = 0;
    var memory_map_self_index: u64 = 0;

    fn init() void {
        if (limine_mem_map.response) |response| {
            memmap_entries = response.entries();
            for (memmap_entries, 0..) |value, index| {
                if (value.kind == .usable) {
                    var tmp_size = value.length / PAGE_SIZE;
                    total_pages += tmp_size;
                    // Overwrite the original memory map
                    memmap_entries[index].length = tmp_size * PAGE_SIZE;
                }
            }
        } else {
            @panic("get limine memory map fails!");
        }

        // Get the number of pages occupied by the memory mapped array
        memmap_pages = (total_pages + PAGE_SIZE - 1) / PAGE_SIZE;
        free_pages = total_pages - memmap_pages;

        for (memmap_entries) |value| {
            if (value.kind == .usable and value.length > total_pages) {
                memory_map = @as([*]u8, @ptrFromInt(value.base))[0..total_pages];
                break;
            }
        }

        @memset(memory_map, 0);

        {
            for (memmap_entries) |value| {
                if (value.base == @intFromPtr(memory_map.ptr)) {
                    break;
                }
                memory_map_self_index += value.length / PAGE_SIZE;
            }

            @memset(memory_map[memory_map_self_index .. memory_map_self_index + memmap_pages], 1);
        }
    }

    fn map_index_to_addr(index: u64) usize {
        var tmp_index = index;
        for (memmap_entries) |entry| {
            if (tmp_index < entry.length / PAGE_SIZE) {
                return entry.base + tmp_index * PAGE_SIZE;
            }
            tmp_index -= entry.length / PAGE_SIZE;
        }

        return 0;
    }

    pub fn allocate_page() usize {
        var map_index: u64 = 0;
        for (memmap_entries) |entry| {
            for (0..entry.length / PAGE_SIZE) |_| {
                if (memory_map[map_index] == 0) {
                    memory_map[map_index] = 1;
                    return map_index_to_addr(map_index);
                }
                map_index += 1;
            }
        }
        unreachable;
    }

    pub fn free_page(addr: usize) void {
        var map_index: u64 = 0;
        for (memmap_entries) |entry| {
            if (addr < entry.base + entry.length) {
                map_index += (addr - entry.base) / PAGE_SIZE;
                break;
            }
            map_index += entry.length / PAGE_SIZE;
        }

        if (map_index >= memory_map_self_index and map_index < memory_map_self_index + memmap_pages) {
            @panic("Error, you are trying to free the memory table records");
        }

        if (memory_map[map_index] == 0) {
            @panic("Error, you are trying to free a free physical memory");
        }

        memory_map[map_index] = 0;
    }
};

const V_MEM = struct {
    const canonical_high_addr = 0xffff800000000000;
    const canonical_low_addr = 0xffff800000000000;

    var PML4: *[512]PageMapLevel4Entry = undefined;

    const PDPT = *[512]PageDirPointerTableEntry;
    const PDT = *[512]PageDirTableEntry;
    const PT = *[512]PageTableEntry;

    fn init() void {
        // in this scopr, we find the limine PML4, and convert it to virtual address
        // then we can easily control it
        {
            if (limine_HHDM.response) |response| {
                var PML4_paddr = cpu.get_PML4();
                var PML4_ptr = PML4_paddr + response.offset;
                PML4 = @ptrFromInt(PML4_ptr);
                {
                    // remap memory_map to high address
                    // replace memory_map to high address
                    var memory_map_ptr = @intFromPtr(P_MEM.memory_map.ptr);
                    P_MEM.memory_map = @as([*]u8, @ptrFromInt(memory_map_ptr + response.offset))[0..P_MEM.total_pages];
                }
            } else {
                @panic("get HHDM response fails");
            }
        }

        // attempt to clear low half virtual address
        {
            // TODO: here is error
            // @memset(@as([*]u8, @ptrCast(PML4))[0 .. 256 * @sizeOf(PageMapLevel4Entry)], 0);
            @memset(PML4[0..256], PageMapLevel4Entry{});
            // @compileLog(@sizeOf(PageMapLevel4Entry));
        }

        idt.register(14, pageFault);
    }

    fn pageFault() noreturn {
        const interrupt_context = idt.context;
        const address = cpu.readCR2();
        var code: *ERROR_CODE = @ptrCast(@volatileCast(&interrupt_context.error_code));

        tty.panicf(
            \\PAGE FAULT
            \\ address:     0x{x}
            \\ error:       {s}
            \\ operation:   {s}
            \\ privilege:   {s}
        , .{
            address,
            if (code.present == 1) "protection" else "none present",
            if (code.write == 1) "write" else "read",
            if (code.user == 1) "user" else "kernel",
        });
    }

    //
    // 9 bit PML4I (page map level 4 index)	9 bit PDPTI (page directory pointer table index)	9 bit PDI (page directory index)	9 bit PTI (page table index)	12 bit offset

    pub fn PML4I(addr: u64) u9 {
        return @truncate((addr >> (9 + 9 + 9 + 12)) & 0x1ff);
    }

    pub fn PDPTI(addr: u64) u9 {
        return @truncate((addr >> (9 + 9 + 12)) & 0x1ff);
    }

    pub fn PDTI(addr: u64) u9 {
        return @truncate((addr >> (9 + 12)) & 0x1ff);
    }

    pub fn PTI(addr: u64) u9 {
        return @truncate((addr >> 12) & 0x1ff);
    }

    pub fn OFFSET(addr: u64) u12 {
        return @truncate(addr & 0xfff);
    }

    const PageMapLevel4Entry = packed struct {
        present: u1 = 0,
        writeable: u1 = 0,
        user_access: u1 = 0,
        write_through: u1 = 0,
        cache_disabled: u1 = 0,
        accessed: u1 = 0,
        ignored_1: u1 = 0,
        reserved_1: u1 = 0,
        ignored_2: u3 = 0,
        HLAT: u1 = 0,
        paddr: u40 = 0,
        ignored_3: u11 = 0,
        execute_disable: u1 = 0,
    };

    const PageDirPointerTableEntry = packed struct {
        present: u1,
        writeable: u1,
        user_access: u1,
        write_through: u1,
        cache_disabled: u1,
        accessed: u1,
        ignored_1: u1,
        page_size: u1, // must be 0
        ignored_2: u3,
        HLAT: u1,
        paddr: u40,
        ignored_3: u11,
        execute_disable: u1,
    };

    const PageDirTableEntry = packed struct {
        present: u1,
        writeable: u1,
        user_access: u1,
        write_through: u1,
        cache_disabled: u1,
        accessed: u1,
        ignored_1: u1,
        page_size: u1, // must be 0
        ignored_2: u3,
        HLAT: u1,
        paddr: u40,
        ignored_3: u11,
        execute_disable: u1,
    };

    const PageTableEntry = packed struct {
        present: u1,
        writeable: u1,
        user_access: u1,
        write_through: u1,
        cache_disabled: u1,
        accessed: u1,
        dirty: u1,
        PAT: u1,
        global: u1,
        ignored_1: u3,
        HLAT: u1,
        paddr: u40,
        ignored_2: u7,
        protection: u4, // if CR4.PKE = 1 or CR4.PKS = 1, this may control the page’s access rights
        execute_disable: u1,
    };

    /// Can only be used when a page fault occurs
    const ERROR_CODE = packed struct {
        // When set, the page fault was caused by a page-protection violation. When not set, it was caused by a non-present page.
        present: u1,
        // When set, the page fault was caused by a write access. When not set, it was caused by a read access.
        write: u1,
        // When set, the page fault was caused while CPL = 3. This does not necessarily mean that the page fault was a privilege violation.
        user: u1,
        // When set, one or more page directory entries contain reserved bits which are set to 1. This only applies when the PSE or PAE flags in CR4 are set to 1.
        reserved_write: u1,
        // When set, the page fault was caused by an instruction fetch. This only applies when the No-Execute bit is supported and enabled.
        instruction_fetch: u1,
        // When set, the page fault was caused by a protection-key violation. The PKRU register (for user-mode accesses) or PKRS MSR (for supervisor-mode accesses) specifies the protection key rights
        protection: u1,
        // When set, the page fault was caused by a shadow stack access.
        shadow_stack: u1,
        // when set, the page fault was caused during HLAT paging.
        HALT: u1,
        // reserved to zero
        reserved_1: u7,
        // when set, the page fault was related to SGX.
        // A pivot by Intel in 2021 resulted in the deprecation of SGX from the 11th and 12th generation Intel Core Processors, but development continues on Intel Xeon for cloud and enterprise use.
        SGX: u1,
        // reserved to zero
        reserved_2: u16,
        zero_padding: u32,
    };

    pub fn high_half_2_paddr(virtual_addr: usize) usize {
        if (virtual_addr < canonical_high_addr) {
            tty.panicf("sorry, you pass a non-high-address: 0x{x}", virtual_addr);
        }

        var offset = limine_HHDM.response.?.offset;
        if (virtual_addr > limine_kernel_addr.response.?.virtual_base) {
            tty.println("a virtual addr which is higher than kernel_addr to paddr", virtual_addr);
        }

        return virtual_addr - offset;
    }

    pub fn paddr_2_high_half(paddr: usize) usize {
        if (paddr > canonical_low_addr) {
            tty.panicf("sorry, you pass a non-low-address: 0x{x}", paddr);
        }

        var offset = limine_HHDM.response.?.offset;

        return paddr + offset;
    }
};
