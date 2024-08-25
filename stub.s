; SPDX-FileCopyrightText: 2023 Andreas Sig Rosvall
;
; SPDX-License-Identifier: GPL-3.0-or-later

; Position indepedent flasher stub for CC2531 OEM flasher hack.

; As the bootloader image fits in 1 flash page, we'll only have to do a single
; erase+write using dma.
; We're running from SRAM, using the XMAP feature of the CC253x, which means
; xdata address 0 corresponds to code address 0x8000 and vice versa.

; Compile and link with:
;    sdas8051 -pwlo stub.rel stub.s
;    sdld -nui stub.ihx stub.rel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Various constants

; CC2531 flash page size is 2kB
FLASH_PAGE_SIZE = 1024*2

; CC2531 has 8 kB SRAM
SRAM_SIZE       = 8*1024
; The data address space is 256 bytes
DATA_SIZE       = 256

; Size of bootloader image to be flashed
; For simplicity, we'll just flash the entire 2kB page, including whatever
; garbage happens to immediately follow the bootloader image when copied from
; ram. This shouldn't matter.
IMG_LEN         = FLASH_PAGE_SIZE

; CC2531 special function registers
DMA0CFGL        = 0xd4
DMA0CFGH        = 0xd5
DMAARM          = 0xd6
DMAREQ          = 0xd7
WDCTL           = 0xc9
; Special function registers in xdata
FCTL            = 0x6270
FADDRL          = 0x6271
FADDRH          = 0x6272
FWDATA          = 0x6273

; DMA register/configuration bits
CH0             =    1 << 0
TRIG_FLASH      =   18 << 0
SRC_INC_1       = 0b01 << 6
PRIO_HIGH       = 0b10 << 0

; Flash FCTL register bits
FCTL_ERASE      = 0
FCTL_WRITE      = 1
FCTL_BUSY       = 7

; Watchdog register bits
WD_ENABLE       = 0b10 << 2
WD_2MS          = 0b11 << 0

; Board specific: USB Data+ pin connected to P1.0
USB_DPLUS_PIN   = P1.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.area REG_BANK_0 (XDATA,ABS)
; The data address space can be found in the xdata address space at the top
; of SRAM
.org SRAM_SIZE - DATA_SIZE

; We'll use the numbered registers to store the dma configuration.
; Aside from being a fun hack, we'll also avoid stomping on the bootloader
; image (by being in the data address space) and save a few bytes using
; register addressing mode when writing out the configuration.

dma_conf:
ar0:	.ds 1 ; src h
ar1:	.ds 1 ; src l
ar2:	.ds 1 ; dst h
ar3:	.ds 1 ; dst l
ar4:	.ds 1 ; len h
ar5:	.ds 1 ; len l
ar6:	.ds 1 ; cfg h
ar7:	.ds 1 ; cfg l


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.area CSEG (CODE)

STUB_SIZE = stub_end - stub_start

stub_start:
	; Disable interrupts!
	clr ea

	; Let's be polite, and let the USB host know that we're down
	clr USB_DPLUS_PIN

	; dma_conf starts at r0, which is 0 in data address space.
	; In a CC253x, the data address space is in xdata at the top of SRAM.
	; For a CC2531 with 8 kB, data address 0 corresponds to xdata address
	; 0x1f00.
	mov DMA0CFGH, #dma_conf >> 8
	mov DMA0CFGL, #dma_conf

	; To write a DMA configuration, we'll need the absolute address of
	; `bootloader_img` in xdata address space.
	; We'll assume that we got here by returning, which means the
	; address of `stub_start` (in code address space) was just popped of
	; the stack, so we can just add 2 to the stack pointer and pop it
	; again.
	inc sp
	inc sp
	; pop MSB of stub_start
	pop ar1
	; pop LSB of stub_start
	pop a

	; Now we have stub_start (in code address space). We want 
	; bootloader_img (in xdata address space), so we need to calculate
	;     bootloader_img = (stub_start + STUB_SIZE) & ~0x8000

	; Add `STUB_SIZE` to get address of `bootloader_img` in code space
	add a, #STUB_SIZE
	xch a, r1
	addc a, #STUB_SIZE >> 8
	; Clear most significant bit to convert from code address to xdata
	; address
	clr a.7

	; DMA configuration
	mov r0, a              ; src h
	; already in r1        ; src l
	mov r2, #FWDATA >> 8   ; dst h
	mov r3, #FWDATA        ; dst l
	mov r4, #IMG_LEN >> 8  ; len h
	mov r5, #IMG_LEN       ; len l
	mov r6, #TRIG_FLASH    ; cfg h
	mov r7, #SRC_INC_1     ; cfg l

	; Load our DMA config and arm the channel
	mov DMAARM, #CH0

	; Set flash address to 0x0000 (page 0, offset 0)
	mov dptr, #FADDRL
	clr a
	movx @dptr, a
	inc dptr
	movx @dptr, a

	; Erase flash page and start writing
	; Flash controller will trigger DMA
	mov dptr, #FCTL
	mov a, #(1 << FCTL_ERASE) | (1 << FCTL_WRITE)
	movx @dptr, a

loop_while_flashing:
	movx a, @dptr
	jb acc + FCTL_BUSY, loop_while_flashing

	; We're done! Now we just need to reboot.

	; Enable watchdog
	mov WDCTL, #WD_ENABLE | WD_2MS
	; Loop until watchdog forces a reboot into the bootloader
	sjmp .

stub_end:
bootloader_img:
	; Bootloader image to be flashed immediately following
