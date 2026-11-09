#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

base_dir = "/home/user/project_dump"
os.makedirs(os.path.join(base_dir, "binaries"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "logs"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "models"), exist_ok=True)

def compress_crle(data: bytes) -> bytes:
    compressed = b"CRLE"
    i = 0
    while i < len(data):
        char = data[i:i+1]
        count = 1
        while i + count < len(data) and data[i+count:i+count+1] == char and count < 255:
            count += 1
        compressed += struct.pack("B", count) + char
        i += count
    return compressed

# 1. Raw ELF file
elf_data = b"\x7fELF" + (b"\x00" * 20) + struct.pack("<Q", 0x401000)
with open(os.path.join(base_dir, "binaries", "app_x"), "wb") as f:
    f.write(elf_data)

# 2. Raw WAL file
wal_data = b"\x37\x7f\x06\x82" + (b"\x00" * 4) + struct.pack(">I", 8192)
with open(os.path.join(base_dir, "logs", "db_log"), "wb") as f:
    f.write(wal_data)

# 3. Raw GCode file
gcode_data = b"; FLAVOR:Marlin\nM104 S200\nG28\nG1 X10 Y10\nG1 X20 Y20\nM109\nG1 Z0.2\n"
with open(os.path.join(base_dir, "models", "shape"), "wb") as f:
    f.write(gcode_data)

# 4. Compressed ELF file
elf_data_2 = b"\x7fELF" + (b"\x00" * 20) + struct.pack("<Q", 0x80000000)
with open(os.path.join(base_dir, "binaries", "app_y_comp"), "wb") as f:
    f.write(compress_crle(elf_data_2))

# 5. Compressed WAL file
wal_data_2 = b"\x37\x7f\x06\x83" + (b"\x00" * 4) + struct.pack(">I", 16384)
with open(os.path.join(base_dir, "logs", "db_log_comp"), "wb") as f:
    f.write(compress_crle(wal_data_2))

# 6. Compressed GCode file
gcode_data_2 = b"; FLAVOR:Marlin\n" + (b"G1 X10\n" * 5) + b"M140 S60\n"
with open(os.path.join(base_dir, "models", "shape_comp"), "wb") as f:
    f.write(compress_crle(gcode_data_2))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
