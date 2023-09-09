This is just an experimental kernel. It only implements memory allocation and a shell. It does not implement multi-threading.

compile:

system: archlinux
tools:
 - qemu-full(extra)
 - bochs(aur)
 - xorriso(extra)
 - mtools(extra)
 - zig(0.11.0)

 compile command:

```sh
make qemu-grub
```
