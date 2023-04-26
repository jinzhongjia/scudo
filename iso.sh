#!/bin/sh

cp zig-out/bin/zos              run/iso/boot/
# cp servers/terminal/terminal run/iso/servers/
# cp servers/keyboard/keyboard run/iso/servers/
# cp servers/shell/shell       run/iso/servers/

grub-mkrescue -o run/zos.iso run/iso/
