SRC = stub.s

FLASHER = oem_flasher.py
LICENSE = LICENSES/GPL-3.0-or-later.txt

STUB = stub.bin

REL = $(SRC:%.s=%.rel)
LST = $(SRC:%.s=%.lst)
RST = $(SRC:%.s=%.rst)
IHX = $(SRC:%.s=%.ihx)

BOOTLOADER_DIR = bootloader
BOOTLOADER_BIN = bootloader.bin
BOOTLOADER = $(BOOTLOADER_DIR)/$(BOOTLOADER_BIN)

BINDIST = dist.tar.gz

GENERATED = $(STUB) $(REL) $(IHX) $(LST) $(RST) $(BINDIST)

all: $(STUB) $(BOOTLOADER)

bindist: $(BINDIST)

$(BINDIST): $(FLASHER) $(STUB) $(BOOTLOADER) $(LICENSE)
	tar -cvz -f $@ $^

flash: $(STUB) $(BOOTLOADER)
	python $(FLASHER) $(STUB) $(BOOTLOADER)

$(BOOTLOADER):
	make -C $(BOOTLOADER_DIR) $(BOOTLOADER_BIN)

clean:
	rm -f $(GENERATED)

%.rel: %.s
	sdas8051 -pwlo $@ $<

%.ihx: %.rel
	sdld -nui $@ $<

%.bin: %.ihx
	objcopy --input-target=ihex --output-target=binary $< $@

.PHONY: clean flash all bindist
