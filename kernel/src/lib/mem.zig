const limine = @import("limine");
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");

const PAGE_SIZE = 0x1000;

export var limine_mem_map: limine.MemoryMapRequest = .{};
export var limine_HHDM: limine.HhdmRequest = .{};

pub fn init() void {
    P_MEM.init();
    V_MEM.init();
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
    var PML4: *[512]PageMapLevel4Entry = undefined;

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
    }

    //
    // 9 bit PML4I (page map level 4 index)	9 bit PDPTI (page directory pointer table index)	9 bit PDI (page directory index)	9 bit PTI (page table index)	12 bit offset

    pub fn PML4I(addr: u64) u9 {
        return @truncate((addr >> (9 + 9 + 9 + 12)) & 0x1ff);
    }

    pub fn PDPTI(addr: u64) u9 {
        return @truncate((addr >> (9 + 9 + 12)) & 0x1ff);
    }

    pub fn PDI(addr: u64) u9 {
        return @truncate((addr >> (9 + 12)) & 0x1ff);
    }

    pub fn PTI(addr: u64) u9 {
        return @truncate((addr >> 12) & 0x1ff);
    }

    pub fn OFFSET(addr: u64) u12 {
        return @truncate(addr & 0xfff);
    }

    const PageMapLevel4Entry = packed struct {
        present: u1,
        writeable: u1,
        user_access: u1,
        write_through: u1,
        cache_disabled: u1,
        accessed: u1,
        ignored_1: u1,
        reserved_1: u1,
        ignored_2: u3,
        HLAT: u1,
        paddr: u40,
        ignored_3: u11,
        execute_disable: u1,
    };

    const PageDirPointerTablePageDirEntry = packed struct {
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

    const PageDirPageTableEntry = packed struct {
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
};
