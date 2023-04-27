const std = @import("std");
const multiboot_v1 = @import("multiboot").v1;
// const multiboot_v2 = @import("multiboot").v2;
const assembly = @import("cpu").x86.assembly;

// NOTE: assert should be replace with @function panic implemented by us.
const assert = std.debug.assert;

export const header_v1 linksection(".multiboot_v1") = multiboot_v1.Header{};

// export const header_v2 linksection(".multiboot_v2") = multiboot_v2.Header{};

export fn init(magic: u32, info: *const multiboot_v1.Info) void {
    _ = info;

    assert(magic == multiboot_v1.BOOT_MAGIC);

    // assembly.sti();
    assembly.hlt();
}
