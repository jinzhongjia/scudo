override IMAGE_NAME := zos

.PHONY: all
all: $(IMAGE_NAME).iso grub

.PHONY: qemu
qemu: $(IMAGE_NAME).iso
	qemu-system-i386 -boot d -cdrom zos.iso -m 4G

.PHONY: qemu-grub
qemu-grub: grub
	qemu-system-i386 -boot d -cdrom grub-zos.iso -m 4G

.PHONY: bochs
bochs: $(IMAGE_NAME).iso
	bochs -q -f bochsrc

.PHONY: bochs-grub
bochs-grub: grub
	bochs -q -f grub-bochsrc

.PHONY: run
run: kernel
	qemu-system-i386 -kernel zig-out/bin/zos -m 4G

.PHONY: debug
debug:
	qemu-system-i386 -kernel zig-out/bin/zos -m 4G -d in_asm,int -s -S  -append "nokaslr console=ttyS0"

.PHONY: asm
asm:
	qemu-system-i386 -kernel zig-out/bin/zos -m 4G -d in_asm,int

limine:
	git clone https://github.com/limine-bootloader/limine.git --branch=v4.x-branch-binary --depth=1
	$(MAKE) -C limine

.PHONY: kernel
kernel:
	zig build	

$(IMAGE_NAME).iso: limine kernel
	rm -rf iso_root
	mkdir -p iso_root
	cp zig-out/bin/zos \
		limine.cfg limine/limine.sys limine/limine-cd.bin limine/limine-cd-efi.bin iso_root/
	xorriso -as mkisofs -b limine-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot limine-cd-efi.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_root -o $(IMAGE_NAME).iso
	limine/limine-deploy $(IMAGE_NAME).iso
	rm -rf iso_root

grub: kernel
	rm -rf iso_root
	mkdir -p iso_root
	mkdir -p iso_root/boot/grub
	mkdir -p iso_root/module
	cp grub.cfg 										iso_root/boot/grub/
	cp zig-out/bin/zos              iso_root/boot/
	cp test 												iso_root/module/
	grub-mkrescue -o grub-zos.iso iso_root/
	rm -rf iso_root


.PHONY: clean
clean:
	rm -rf iso_root $(IMAGE_NAME).iso grub-zos.iso

.PHONY: distclean
distclean: clean
	rm -rf limine
