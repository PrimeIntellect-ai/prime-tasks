#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import struct
import os

def rle_compress(data):
    compressed = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        compressed.append(count)
        compressed.append(data[i])
        i += count
    return compressed

files = [
    {
        "name": "readme.txt",
        "type": 0,
        "data": b"Welcome to the robotics documentation.\n" * 5
    },
    {
        "name": "calibrate.gcode",
        "type": 1,
        "data": b"G28 X Y Z\nG1 X100 Y100 F3000\n" * 3
    },
    {
        "name": "firmware_boot.elf",
        "type": 2,
        "data": b"\x7FELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" + b"\x00" * 50
    }
]

with open("/home/user/legacy_docs.bin", "wb") as f:
    f.write(b"DOCP")
    f.write(struct.pack("<I", len(files)))

    for file in files:
        name_bytes = file["name"].encode("ascii")
        name_padded = name_bytes + b"\x00" * (32 - len(name_bytes))
        f.write(name_padded)
        f.write(struct.pack("B", file["type"]))

        comp_data = rle_compress(file["data"])
        f.write(struct.pack("<I", len(comp_data)))
        f.write(comp_data)

os.chmod("/home/user/legacy_docs.bin", 0o644)
'

    chmod -R 777 /home/user
