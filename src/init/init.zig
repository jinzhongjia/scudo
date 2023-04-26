const std = @import("std");
const multiboot = @import("multiboot").v1;
const assembly = @import("cpu").x86.assembly;

// NOTE: assert should be replace with @function panic implemented by us.
const assert = std.debug.assert;

export const header_v1 linksection(".multiboot_v1") = multiboot.Header{};

// export const header_v2 linksection(".multiboot_v2") = multiboot.v2.Header{};

export fn init(magic: u32, info: *const multiboot.Info) void {
    _ = info;

    assert(magic == multiboot.BOOT_MAGIC);

    // assembly.sti();
    assembly.hlt();
}
