SRC = stub.s

STUB = stub.bin

REL = $(SRC:%.s=%.rel)
LST = $(SRC:%.s=%.lst)
RST = $(SRC:%.s=%.rst)
IHX = $(SRC:%.s=%.ihx)

BOOTLOADER_DIR = bootloader
BOOTLOADER_BIN = bootloader.bin
BOOTLOADER = $(BOOTLOADER_DIR)/$(BOOTLOADER_BIN)

GENERATED = $(STUB) $(REL) $(IHX) $(LST) $(RST) 

all: $(STUB) $(BOOTLOADER)

flash: $(STUB) $(BOOTLOADER)
	python oem_flasher.py $(STUB) $(BOOTLOADER)

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

.PHONY: clean flash all
