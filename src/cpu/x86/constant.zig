// The size of a memory page.
pub const PAGE_SIZE: usize = 4096;



////
// Return address as either usize or a pointer of type T.
//
// Arguments:
//     T: The desired output type.
//     address: Address to be returned.
//
// Returns:
//     The given address as type T (usize or a pointer).
//
fn intOrPtr(comptime T: type, address: usize) T {
    return if (T == usize) address else @intToPtr(T, address);
}

////
// Return address as an usize.
//
// Arguments:
//     address: Address to be returned.
//
// Returns:
//     The given address as type usize.
//
fn int(address: anytype) usize {
    return if (@TypeOf(address) == usize) address else @ptrToInt(address);
}

////
// Page-align an address downward.
//
// Arguments:
//     address: Address to align.
//
// Returns:
//     The aligned address.
//
pub fn pageBase(address: anytype) @TypeOf(address) {
    const result = int(address) & (~PAGE_SIZE +% 1);

    return intOrPtr(@TypeOf(address), result);
}

////
// Page-align an address upward.
//
// Arguments:
//     address: Address to align.
//
// Returns:
//     The aligned address.
//
pub fn pageAlign(address: anytype) @TypeOf(address) {
    const result = (int(address) + PAGE_SIZE - 1) & (~PAGE_SIZE +% 1);

    return intOrPtr(@TypeOf(address), result);
}
