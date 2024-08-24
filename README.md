# Flash a stock Texas Instruments CC2531USB-RD dongle, no tools required.

## What?
This is a hack to get your own firmware running on a stock CC2531 USB dongle over USB, without a programmer.
It can only transfer about 3 kB of code, but that is enough to get a short flasher stub and a simple DFU bootloader onto the dongle. From there, you can flash all the firmware you want using [dfu-util](https://sourceforge.net/projects/dfu-util/) or something else that speaks USB device firmware upgrade protocol.

## Why?
Because the TI CC2531 is a fun chip for experimenting with IEEE 802.15.4 WPAN stuff from a desktop computer.

CC2531 based USB dongles [like CC2531USB-RD](https://www.ti.com/tool/CC2531USB-RD) are cheaply available (~$5 from China), but usually comes with the simple packet sniffer firmware that doesn't support upgrading over USB, instead requiring either buying a programming device from TI or hacking something together with an arduino.

## How does it work?
The TI sniffer firmware expects some packet filtering parameters of limited length when it receives a USB control transfer with bmRequestType 0x40 and bRequest 0xD2.
The control transfer payload is written to xdata 0x020F, and the (fat) write pointer is located at 0x0371. As the length of the transfer is not checked, it's possible to overwrite the pointer with an arbitrary address, and have subsequent writes go there.
Additionally, the CC2531 has most special function registers mapped into xdata, and allows running code from xdata. This program exploits those features, by writing the given executable binary to xdata, setting the XMAP bit in the MEMCTR special function register, and finally overwriting a return pointer on stack to
jump to the code written to xdata.

## How to use
Grab [the binary release](https://github.com/rosvall/cc2531_oem_flasher/releases) or follow the build instructions below.

Then:

```sh
# Flash bootloader to CC2531 dongle (that runs stock sniffer firmware)
python oem_flasher.py stub.bin bootloader/bootloader.bin
```

Or use oem_flasher.py to run whatever else code you want on the dongle. The source of both `oem_flasher.py` and `stub.s` is written with readability and hack-ability in mind.

It should be relatively simple to modify dfu_mode.s from the bootloader to run directly from ram, for example.

## Known issues
### Works only for stock firmware with bcdDevice = 83.91 (0x8391) and 8.21 (0x0821)

If you get an error message about your dongle not being supported, please open an issue stating where to get that dongle, and if at all possible, attach a copy of the firmware.

## Build requirements:
- [SDCC](https://sourceforge.net/projects/sdcc/) to assemble and link the flasher stub
- [binutils](https://www.gnu.org/software/binutils/) to convert intel hex to raw binary
- [pyusb](https://github.com/pyusb/pyusb) to run oem_flasher.py
- [make](https://www.gnu.org/software/make/)

## How to build
```sh
# Check out repo with all sub-modules:
git clone --recursive 'https://github.com/rosvall/cc2531_oem_flasher.git' 
cd cc2531_oem_flasher

# Build flasher stub and bootloader
make

# Flash bootloader to CC2531 dongle (that runs stock sniffer firmware)
python oem_flasher.py stub.bin bootloader/bootloader.bin
#or simply
make flash
```


## See also
 - [Simple USB DFU bootloader for TI CC2531](https://github.com/rosvall/cc2531_bootloader)
 - [WPAN Adapter firmware for CC2531 USB Dongle](https://github.com/rosvall/cc2531_usb_wpan_adapter)
 - [Linux kernel driver for CC2531 WPAN Adapter firmware](https://github.com/rosvall/cc2531_linux)
