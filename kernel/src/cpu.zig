pub inline fn hlt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
