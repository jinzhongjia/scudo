const limine = @import("limine");
const idt = @import("idt.zig");
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");
const lib = @import("../lib.zig");
const config = @import("config.zig").mem;

pub const PAGE_SIZE = 0x1000;

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
    // NOTE: this module should be rewrite!!!

    /// this is entries for memory map
    var memmap_entries: []*limine.MemoryMapEntry = undefined;

    var memory_map: []u8 = undefined;

    // page number
    var total_pages: u64 = 0;
    var free_pages: u64 = 0;

    // physical memory array's pages
    var memmap_pages: u64 = 0;
    var memory_map_self_index: u64 = 0;

    var kernel_region_size: u64 = undefined;

    fn init() void {
        if (limine_mem_map.response) |response| {
            memmap_entries = response.entries();
            for (memmap_entries) |value| {
                if (value.kind == .usable) {
                    total_pages += value.length / PAGE_SIZE;
                }
                if (value.kind == .kernel_and_modules) {
                    if (kernel_region_size != 0) {
                        @panic("more than two kernel and file areas");
                    }
                    kernel_region_size = value.length;
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

        if (comptime config.is_print_mem_info) {
            var TOTAL_SIZE = free_pages * PAGE_SIZE;
            switch (config.display_type) {
                0 => {
                    tty.println("available physical memory is {}B", TOTAL_SIZE);
                },
                1 => {
                    tty.println("available physical memory is {}KB", TOTAL_SIZE / 1024);
                },
                2 => {
                    tty.println("available physical memory is {}MB", TOTAL_SIZE / 1024 / 1024);
                },
                3 => {
                    tty.println("available physical memory is {}GB", TOTAL_SIZE / 1024 / 1024 / 1024);
                },
                else => {
                    @panic("display_type should be less than 4");
                },
            }
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
                    free_pages -= 1;
                    return map_index_to_addr(map_index);
                }
                map_index += 1;
            }
        }
        @panic("no more free page to allocate");
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
        free_pages += 1;
    }
};

/// init for vmeme
/// NOTE: we use 4 level paging
pub const V_MEM = struct {
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
                if (config.if_print_HHDM) {
                    tty.println("HHDM is 0x{x}", response.offset);
                }
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

    pub const VIRTUAL_ADDR = struct {
        reserved: u16,
        pml4i: u9,
        pdpti: u9,
        pdti: u9,
        pti: u9,
        offset: u12,

        pub fn init(virtual_addr: usize) VIRTUAL_ADDR {
            return VIRTUAL_ADDR{
                .reserved = RESERVED(virtual_addr),
                .pml4i = PML4I(virtual_addr),
                .pdpti = PDPTI(virtual_addr),
                .pdti = PDTI(virtual_addr),
                .pti = PTI(virtual_addr),
                .offset = OFFSET(virtual_addr),
            };
        }
        fn RESERVED(addr: usize) u16 {
            return @truncate(addr >> (9 + 9 + 9 + 9 + 12));
        }
        fn PML4I(addr: usize) u9 {
            return @truncate((addr >> (9 + 9 + 9 + 12)) & 0x1ff);
        }

        fn PDPTI(addr: usize) u9 {
            return @truncate((addr >> (9 + 9 + 12)) & 0x1ff);
        }

        fn PDTI(addr: usize) u9 {
            return @truncate((addr >> (9 + 12)) & 0x1ff);
        }

        fn PTI(addr: usize) u9 {
            return @truncate((addr >> 12) & 0x1ff);
        }

        fn OFFSET(addr: usize) u12 {
            return @truncate(addr & 0xfff);
        }

        pub fn offset_1G_page(this: VIRTUAL_ADDR) usize {
            return (@as(usize, @intCast(this.pdti)) << (12 + 9)) + (@as(usize, @intCast(this.pti)) << 9) + (@as(usize, @intCast(this.offset)));
        }

        pub fn offset_2M_page(this: VIRTUAL_ADDR) usize {
            return (@as(usize, @intCast(this.pti)) << 9) + (@as(usize, @intCast(this.offset)));
        }
    };

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

    pub fn translate_virtual_address(virtual_addr: usize) ?usize {
        const vaddr = VIRTUAL_ADDR.init(virtual_addr);

        var pdpt: *[512]PageDirPointerTableEntry = undefined;
        {
            const pml4_entry = PML4.*[vaddr.pml4i];

            if (pml4_entry.present != 1) {
                return null;
            }

            pdpt = @ptrFromInt(paddr_2_high_half(pml4_entry.paddr * PAGE_SIZE));
        }

        var pdt: *[512]PageDirTableEntry = undefined;
        {
            const pdpt_entry = pdpt.*[vaddr.pdpti];

            if (pdpt_entry.present != 1) {
                return null;
            }

            if (pdpt_entry.page_size == 1) {
                return pdpt_entry.paddr * PAGE_SIZE + vaddr.offset_1G_page();
            }

            pdt = @ptrFromInt(paddr_2_high_half(pdpt_entry.paddr * PAGE_SIZE));
        }

        var pt: *[512]PageTableEntry = undefined;
        {
            const pdt_entry = pdt.*[vaddr.pdti];
            if (pdt_entry.present != 1) {
                return null;
            }

            if (pdt_entry.page_size == 1) {
                return pdt_entry.paddr * PAGE_SIZE + vaddr.offset_2M_page();
            }

            pt = @ptrFromInt(paddr_2_high_half(pdt_entry.paddr * PAGE_SIZE));
        }

        {
            var pt_entry = pt.*[vaddr.pti];

            if (pt_entry.present != 1) {
                return null;
            }

            return pt_entry.paddr * PAGE_SIZE + vaddr.offset;
        }
    }

    // prevent to use limine's default used address
    fn check_vaddr_legit(vaddr: usize) bool {
        for (P_MEM.memmap_entries) |mmap| {
            var addr = paddr_2_high_half(mmap.base);
            if (addr <= vaddr and vaddr < addr + mmap.length) {
                return false;
            }
        }
        return true;
    }
};
