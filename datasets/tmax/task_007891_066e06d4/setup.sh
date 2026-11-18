#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential tar gzip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_dump

    python3 << 'EOF'
import os
import struct

base_dir = "/home/user/legacy_dump"
os.makedirs(base_dir, exist_ok=True)

# Generate Fake ELF 1: x86_64 (e_machine = 62 / 0x3E)
with open(os.path.join(base_dir, "controller.elf"), "wb") as f:
    # 16 bytes e_ident, 2 bytes e_type, 2 bytes e_machine
    header = b"\x7fELF" + b"\x00"*12 + struct.pack("<H", 2) + struct.pack("<H", 62)
    f.write(header + b"\x00"*50)

# Generate Fake ELF 2: ARM (e_machine = 40 / 0x28)
with open(os.path.join(base_dir, "sensor.elf"), "wb") as f:
    header = b"\x7fELF" + b"\x00"*12 + struct.pack("<H", 2) + struct.pack("<H", 40)
    f.write(header + b"\x00"*50)

# Generate Fake GCode 1: Temp 215
with open(os.path.join(base_dir, "chassis.gcode"), "w") as f:
    f.write("; GCode file\nG28\nM104 S215\nG1 X0 Y0\n")

# Generate Fake GCode 2: Temp 190
with open(os.path.join(base_dir, "bracket.gcode"), "w") as f:
    f.write("; GCode file\nG28\nM104 S190\nG1 X10 Y10\n")
EOF

    chmod -R 777 /home/user
