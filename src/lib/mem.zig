const std = @import("std");
const cpu = @import("cpu");
const tty = @import("tty.zig");
const vmem = @import("vmem.zig");

const mem = std.mem;
const x86 = cpu.x86;

// Standard allocator interface.
pub var allocator = mem.Allocator{
    .ptr = undefined,
    .vtable = &vtable,
};

var vtable = mem.Allocator.VTable{
    .free = free,
    .alloc = alloc,
    .resize = resize,
};

var heap: []u8 = undefined; // Global kernel heap.
var free_list: ?*Block = undefined; // List of free blocks in the heap.

// Structure representing a block in the heap.
pub const Block = struct {
    pub const Self = @This();

    free: bool = true, // Is the block free?

    prev: ?*Block = null, // Adjacent block to the left.
    next: ?*Block = null, // Adjacent block to the right.

    // Doubly linked list of free blocks.
    prev_free: ?*Block = null,
    next_free: ?*Block = null,

    ////
    // Calculate the size of the block.
    //
    // Returns:
    //     The size of the usable portion of the block.
    //
    pub fn size(self: *Self) usize {
        // Block can end at the beginning of the next block, or at the end of the heap.
        const end = if (self.next) |next_block| @ptrToInt(next_block) else @ptrToInt(heap.ptr) + heap.len;
        // End - Beginning - Metadata = the usable amount of memory.
        return end - @ptrToInt(self) - @sizeOf(Block);
    }

    ////
    // Return a slice of the usable portion of the block.
    //
    pub fn data(self: *Block) [*]u8 {
        return @intToPtr([*]u8, @ptrToInt(self) + @sizeOf(Block));
    }

    ////
    // Get the block metadata from the associated slice of memory.
    //
    // Arguments:
    //     bytes: The usable portion of the block.
    //
    // Returns:
    //     The associated block structure.
    //
    pub fn fromData(bytes: [*]u8) *Block {
        return @intToPtr(*Block, @ptrToInt(bytes) - @sizeOf(Block));
    }
};

// Implement standard alloc function - see std.mem for reference.
fn alloc(_: *anyopaque, size: usize, _: u8, _: usize) ?[*]u8 {
    // TODO: align properly.

    // Find a block that's big enough.
    if (searchFreeBlock(size)) |block| {
        // If it's bigger than needed, split it.
        if (block.size() > size + @sizeOf(Block)) {
            splitBlock(block, size);
        }
        occupyBlock(block); // Remove the block from the free list.

        // var alloc_mem = block.data()[0..size];
        // _ = alloc_mem;
        return block.data();
    }
    return null;
}

// Implement standard realloc function - see std.mem for reference.
fn resize(_: *anyopaque, old_mem: []u8, _: u8, new_size: usize, _: usize) bool {
    // Try to increase the size of the current block.
    var block = Block.fromData(old_mem.ptr);
    mergeRight(block);

    // If the enlargement succeeded:
    if (block.size() >= new_size) {
        // If there's extra space we don't need, split the block.
        if (block.size() >= new_size + @sizeOf(Block)) {
            splitBlock(block, new_size);
        }
        return true; // We can return the old pointer.
    }
    return false;
}

// Implement standard free function - see std.mem for reference.
fn free(_: *anyopaque, old_mem: []u8, _: u8, _: usize) void {
    var block = Block.fromData(old_mem.ptr);

    freeBlock(block); // Reinsert the block in the free list.
    // Try to merge the free block with adjacent ones.
    mergeRight(block);
    mergeLeft(block);
}

////
// Search for a free block that has at least the required size.
//
// Arguments:
//     size: The size of the usable portion of the block.
//
// Returns:
//     A suitable block, or null.
//
fn searchFreeBlock(size: usize) ?*Block {
    var i = free_list;

    while (i) |block| : (i = block.next_free) {
        if (block.size() >= size) return block;
    }

    return null;
}

////
// Flag a block as free and add it to the free list.
//
// Arguments:
//     block: The block to be freed.
//
fn freeBlock(block: *Block) void {
    if (block.free == true) {
        tty.panic("Free a free block", .{});
    }

    // Place the block at the front of the list.
    block.free = true;
    block.prev_free = null;
    block.next_free = free_list;
    if (free_list) |first| {
        first.prev_free = block;
    }
    free_list = block;
}

////
// Remove a block from the free list and flag it as busy.
//
// Arguments:
//     block: The block to be occupied.
//
fn occupyBlock(block: *Block) void {
    if (block.free == false) {
        tty.panic("Free a free block", .{});
    }
    if (block.prev_free) |prev_free| {
        // If there's a preceding block, update it.
        prev_free.next_free = block.next_free;
    } else {
        // Otherwise, we are at the beginning of the list.
        free_list = block.next_free;
    }

    // If the block is not the last, we also need to update its successor.
    if (block.next_free) |next_free| {
        next_free.prev_free = block.prev_free;
    }

    block.free = false;
}

fn unsafeIntToPtr(comptime Ptr: type, int: anytype) Ptr {
  @setRuntimeSafety(false);
  return @intToPtr(Ptr, int);
}

////
// Reduce the size of a block by splitting it in two. The second part is
// marked free. The first part can be either free or busy (depending on
// the original block).
//
// Arguments:
//     block: The block to be split.
//
fn splitBlock(block: *Block, left_sz: usize) void {
    // Check that there is enough space for a second block.

    if (block.size() - left_sz <= @sizeOf(Block)) {
        // TODO: this panic should be changed!
        tty.panic("split block error, block is small", .{});
    }

    // Setup the second block at the end of the first one.
    var tmp = @ptrToInt(block) + @sizeOf(Block) + left_sz;
    // tty.println("{x}", .{tmp});
    var right_block = unsafeIntToPtr(*Block, tmp);

    right_block.* = Block{
        .free = false, // For consistency: not free until added to the free list.
        .prev = block,
        .next = block.next,
        .prev_free = null,
        .next_free = null,
    };
    // right_block.*.free = false;
    // right_block.*.prev = block;
    // right_block.*.next = block.next;
    // right_block.*.next_free = null;
    // right_block.*.prev_free = null;
    block.next = right_block;

    // Update the block that comes after.
    if (right_block.next) |next| {
        next.prev = right_block;
    }

    freeBlock(right_block); // Set the second block as free.
}

////
// Try to merge a block with a free one on the right.
//
// Arguments:
//     block: The block to merge (not necessarily free).
//
fn mergeRight(block: *Block) void {
    // If there's a block to the right...
    if (block.next) |next| {
        // ...and it's free:
        if (next.free) {
            // Remove it from the list of free blocks.
            occupyBlock(next);
            // Merge it with the previous one.
            block.next = next.next;
            if (next.next) |next_next| {
                next_next.prev = block;
            }
        }
    }
}

////
// Try to merge a block with a free one on the left.
//
// Arguments:
//     block: The block to merge (not necessarily free).
//
fn mergeLeft(block: *Block) void {
    if (block.prev) |prev| {
        if (prev.free) {
            mergeRight(prev);
        }
    }
}

////
// Initialize the dynamic memory allocation system.
//
// Arguments:
//     capacity: Maximum size of the kernel heap.
//
pub fn initialize(capacity: usize) void {
    tty.step("Initializing Dynamic Memory Allocation", .{});

    // Ensure the heap doesn't overflow into user space.
    if (x86.layout.HEAP + capacity >= x86.layout.USER_STACKS) {
        tty.panic("capacity is too large!", .{});
    }

    // Map the required amount of virtual (and physical memory).
    vmem.mapZone(x86.layout.HEAP, null, capacity, vmem.PAGE_WRITE | vmem.PAGE_GLOBAL);
    // TODO: on-demand mapping.

    heap = @intToPtr([*]u8, x86.layout.HEAP)[0..capacity];
    free_list = @ptrCast(*Block, @alignCast(@alignOf(Block), heap.ptr));

    free_list.?.* = Block{};

    tty.ColorPrint(tty.Color.White, " {d}KB", .{capacity / 1024});

    tty.stepOK();
}
