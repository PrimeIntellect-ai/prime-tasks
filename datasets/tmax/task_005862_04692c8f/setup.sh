#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/machine_data/folder_A/folder_B
    mkdir -p /home/user/machine_data/folder_C

    # Create symlink loop
    ln -s /home/user/machine_data /home/user/machine_data/folder_A/folder_B/loop_link
    ln -s /home/user/machine_data/folder_A /home/user/machine_data/folder_C/loop_link2

    # Create GCode files (Shift-JIS)
    python3 -c '
import os
content1 = "G01 X10 Y20 ; テスト\nG02 X30 Y40 ; 終了\n"
content2 = "G00 Z100 ; 安全位置\n"
with open("/home/user/machine_data/part1.gcode", "wb") as f:
    f.write(content1.encode("shift_jis"))
with open("/home/user/machine_data/folder_A/part2.gcode", "wb") as f:
    f.write(content2.encode("shift_jis"))
'

    # Create WAL files (Hex text)
    python3 -c '
import os
# wal1: 5 bytes of 00, 300 bytes of FF, 2 bytes of 01
wal1_bin = b"\x00"*5 + b"\xFF"*300 + b"\x01"*2
wal1_hex = " ".join(f"{b:02x}" for b in wal1_bin)

# wal2: alternating
wal2_bin = b"\x10\x20\x30\x40" * 2
wal2_hex = " ".join(f"{b:02x}" for b in wal2_bin)

with open("/home/user/machine_data/folder_C/log1.wal", "w") as f:
    f.write(wal1_hex)
with open("/home/user/machine_data/folder_A/folder_B/log2.wal", "w") as f:
    f.write(wal2_hex)
'

    chmod -R 777 /home/user
