const limine = @import("limine");
const tty = @import("tty.zig");

const PAGE_SIZE = 0x1000;

pub export var limine_mem_map: limine.MemoryMapRequest = .{};

pub fn init() void {
    P_MEM.init();
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

        // tty.println("total pages is {}, free pages is {}", .{ total_pages, free_pages });
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
        @panic("allocate_page fails!");
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
