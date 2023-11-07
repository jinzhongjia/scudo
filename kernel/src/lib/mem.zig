const limine = @import("limine");
const idt = @import("idt.zig");
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");
const lib = @import("../lib.zig");
const config = @import("config").mem;

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

    pub fn get_free_pages() u64 {
        return free_pages;
    }
};

pub fn is_aligned(addr: usize) bool {
    return addr % PAGE_SIZE == 0;
}

/// init for vmeme
/// NOTE: we use 4 level paging
pub const V_MEM = struct {
    const canonical_high_addr = 0xffff800000000000;
    const canonical_low_addr = 0xffff800000000000;

    const PML4T = *[512]PageMapLevel4Entry;
    const PDPT = *[512]PageDirPointerTableEntry;
    const PDT = *[512]PageDirTableEntry;
    const PT = *[512]PageTableEntry;

    var PML4: PML4T = undefined;

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

        idt.register_handle(14, pageFault);
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
            if (code.present) "protection" else "none present",
            if (code.write) "write" else "read",
            if (code.user) "user" else "kernel",
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
        present: bool = false,
        writeable: bool = false,
        user_access: bool = false,
        write_through: bool = false,
        cache_disabled: bool = false,
        accessed: bool = false,
        ignored_1: bool = false,
        reserved_1: bool = false,
        ignored_2: u3 = 0,
        HLAT: bool = false,
        paddr: u40 = 0,
        ignored_3: u11 = 0,
        execute_disable: bool = false,
    };

    comptime {
        if (@sizeOf(PageMapLevel4Entry) != 8) {
            @panic("PageMapLevel4Entry size is not correct");
        }
    }

    const PageDirPointerTableEntry = packed struct {
        present: bool = false,
        writeable: bool = false,
        user_access: bool = false,
        write_through: bool = false,
        cache_disabled: bool = false,
        accessed: bool = false,
        ignored_1: bool = false,
        page_size: bool = false, // must be 0
        ignored_2: u3 = 0,
        HLAT: bool = false,
        paddr: u40 = 0,
        ignored_3: u11 = 0,
        execute_disable: bool = false,
    };

    comptime {
        if (@sizeOf(PageDirPointerTableEntry) != 8) {
            @panic("PageDirPointerTableEntry size is not correct");
        }
    }

    const PageDirTableEntry = packed struct {
        present: bool = false,
        writeable: bool = false,
        user_access: bool = false,
        write_through: bool = false,
        cache_disabled: bool = false,
        accessed: bool = false,
        ignored_1: bool = false,
        page_size: bool = false, // must be 0
        ignored_2: u3 = 0,
        HLAT: bool = false,
        paddr: u40 = 0,
        ignored_3: u11 = 0,
        execute_disable: bool = false,
    };

    comptime {
        if (@sizeOf(PageDirTableEntry) != 8) {
            @panic("PageDirTableEntry size is not correct");
        }
    }

    const PageTableEntry = packed struct {
        present: bool = false,
        writeable: bool = false,
        user_access: bool = false,
        write_through: bool = false,
        cache_disabled: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        PAT: bool = false,
        global: bool = false,
        ignored_1: u2 = 0,
        HLAT: bool = false,
        paddr: u40 = 0,
        ignored_2: u7 = 0,
        protection: u4 = 0, // if CR4.PKE = 1 or CR4.PKS = 1, this may control the page’s access rights
        execute_disable: bool = false,
    };

    comptime {
        if (@sizeOf(PageTableEntry) != 8) {
            @panic("PageTableEntry size is not correct");
        }
    }

    /// Can only be used when a page fault occurs
    const ERROR_CODE = packed struct {
        // When set, the page fault was caused by a page-protection violation. When not set, it was caused by a non-present page.
        present: bool = false,
        // When set, the page fault was caused by a write access. When not set, it was caused by a read access.
        write: bool = false,
        // When set, the page fault was caused while CPL = 3. This does not necessarily mean that the page fault was a privilege violation.
        user: bool = false,
        // When set, one or more page directory entries contain reserved bits which are set to 1. This only applies when the PSE or PAE flags in CR4 are set to 1.
        reserved_write: bool = false,
        // When set, the page fault was caused by an instruction fetch. This only applies when the No-Execute bit is supported and enabled.
        instruction_fetch: bool = false,
        // When set, the page fault was caused by a protection-key violation. The PKRU register (for user-mode accesses) or PKRS MSR (for supervisor-mode accesses) specifies the protection key rights
        protection: bool = false,
        // When set, the page fault was caused by a shadow stack access.
        shadow_stack: bool = false,
        // when set, the page fault was caused during HLAT paging.
        HALT: bool = false,
        // reserved to zero
        reserved_1: u7 = 0,
        // when set, the page fault was related to SGX.
        // A pivot by Intel in 2021 resulted in the deprecation of SGX from the 11th and 12th generation Intel Core Processors, but development continues on Intel Xeon for cloud and enterprise use.
        SGX: bool = false,
        // reserved to zero
        reserved_2: u16 = 0,
        zero_padding: u32 = 0,
    };

    comptime {
        if (@sizeOf(ERROR_CODE) != 8) {
            @panic("error_code size is not correct");
        }
    }

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

        var pdpt: PDPT = undefined;
        {
            const pml4_entry: *PageMapLevel4Entry = &PML4[vaddr.pml4i];

            if (!pml4_entry.present) {
                return null;
            }

            pdpt = @ptrFromInt(paddr_2_high_half(pml4_entry.paddr * PAGE_SIZE));
        }

        var pdt: PDT = undefined;
        {
            const pdpt_entry: *PageDirPointerTableEntry = &pdpt[vaddr.pdpti];

            if (!pdpt_entry.present) {
                return null;
            }

            if (pdpt_entry.page_size) {
                return pdpt_entry.paddr * PAGE_SIZE + vaddr.offset_1G_page();
            }

            pdt = @ptrFromInt(paddr_2_high_half(pdpt_entry.paddr * PAGE_SIZE));
        }

        var pt: PT = undefined;
        {
            const pdt_entry: *PageDirTableEntry = &pdt[vaddr.pdti];

            if (!pdt_entry.present) {
                return null;
            }

            if (pdt_entry.page_size) {
                return pdt_entry.paddr * PAGE_SIZE + vaddr.offset_2M_page();
            }

            pt = @ptrFromInt(paddr_2_high_half(pdt_entry.paddr * PAGE_SIZE));
        }

        {
            const pt_entry: *PageTableEntry = &pt[vaddr.pti];

            if (!pt_entry.present) {
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

    pub fn map(physical: usize, virtual: usize, size: enum {
        big,
        medium,
        small,
    }) void {
        _ = size;
        lib.assert(@src(), is_aligned(physical));
        lib.assert(@src(), is_aligned(virtual));

        const vaddr = VIRTUAL_ADDR.init(virtual);

        var pml4 = PML4;
        var pml4_entry: *PageMapLevel4Entry = undefined;

        var pdpt: PDPT = undefined;
        var pdpt_entry: *PageDirPointerTableEntry = undefined;

        var pdt: PDT = undefined;
        var pdt_entry: *PageDirTableEntry = undefined;

        var pt: PT = undefined;
        var pt_entry: *PageTableEntry = undefined;

        pml4_entry = &pml4[vaddr.pml4i];
        if (pml4_entry.present) {
            pdpt = @ptrFromInt(paddr_2_high_half(pml4_entry.paddr * PAGE_SIZE));
        } else {
            const paddr_tmp = P_MEM.allocate_page();

            pml4_entry.present = true;
            pml4_entry.writeable = true;
            pml4_entry.paddr = @truncate(paddr_tmp / PAGE_SIZE);

            const vaddr_tmp = paddr_2_high_half(paddr_tmp);
            zero_page(vaddr_tmp);

            pdpt = @ptrFromInt(vaddr_tmp);
        }

        pdpt_entry = &pdpt[vaddr.pdpti];
        if (pdpt_entry.present) {
            pdt = @ptrFromInt(paddr_2_high_half(pdpt_entry.paddr * PAGE_SIZE));
        } else {
            const paddr_tmp = P_MEM.allocate_page();

            pdpt_entry.present = true;
            pdpt_entry.writeable = true;
            pdpt_entry.paddr = @truncate(paddr_tmp / PAGE_SIZE);

            const vaddr_tmp = paddr_2_high_half(paddr_tmp);
            zero_page(vaddr_tmp);

            pdt = @ptrFromInt(vaddr_tmp);
        }

        pdt_entry = &pdt[vaddr.pdti];
        if (pdt_entry.present) {
            pt = @ptrFromInt(paddr_2_high_half(pdt_entry.paddr * PAGE_SIZE));
        } else {
            const paddr_tmp = P_MEM.allocate_page();

            pdt_entry.present = true;
            pdt_entry.writeable = true;
            pdt_entry.paddr = @truncate(paddr_tmp / PAGE_SIZE);

            const vaddr_tmp = paddr_2_high_half(paddr_tmp);
            zero_page(vaddr_tmp);

            pt = @ptrFromInt(vaddr_tmp);
        }

        pt_entry = &pt[vaddr.pti];
        if (pt_entry.present) {
            @panic("you want to remap an present page");
        } else {
            pt_entry.present = true;
            pt_entry.writeable = true;
            pt_entry.paddr = @truncate(physical / PAGE_SIZE);
        }
    }

    // zero one page
    fn zero_page(vaddr: usize) void {
        const ptr: PML4T = @ptrFromInt(vaddr);
        @memset(ptr, PageMapLevel4Entry{});
    }
};
