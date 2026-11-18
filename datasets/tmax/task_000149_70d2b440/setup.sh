#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /home/user/projects/cnc_data/

python3 -c '
import os

def compress_rle(data: bytes) -> bytes:
    compressed = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i] == data[i + count] and count < 255:
            count += 1
        compressed.append(count)
        compressed.append(data[i])
        i += count
    return bytes(compressed)

files = {
    "bracket": """G21 ; Set units to millimeters\nG90 ; Absolute positioning\nG28 ; Home\nG1 Z15.0 F9000\nG1 X50 Y50 F3000\nG1 X50 Y60 E10\nG1 X60 Y60 E20\n M104 S0\n""",
    "gear": """G90\n G1  X10 Y10\nG0 X20 Y20\nG1 X15 Y15\nG1 Z2.0\n""",
    "spacer": """M107\nG28 X0 Y0\nG28 Z0\nG92 E0\nG0 F7200 X20 Y20 Z0.3\nM104 S0\n"""
}

for name, content in files.items():
    utf16_data = content.encode("utf-16le")
    rle_data = compress_rle(utf16_data)
    with open(f"/home/user/projects/cnc_data/{name}.rle", "wb") as f:
        f.write(rle_data)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
