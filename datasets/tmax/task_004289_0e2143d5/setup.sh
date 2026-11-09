#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data/dir1/dir2
    mkdir -p /home/user/raw_data/dir3
    mkdir -p /home/user/categorized/elf
    mkdir -p /home/user/categorized/wal
    mkdir -p /home/user/categorized/gcode

    python3 -c '
import os
files = {
    "/home/user/raw_data/dir1/binary1.elf": b"\x7F\x45\x4C\x46\x01\x02\x03\x04\x00\x00\x00\x00\x00\x00\x00\x00",
    "/home/user/raw_data/dir3/binary2.elf": b"\x7F\x45\x4C\x46\x01\x02\x03\x05\x00\x00\x00\x00\x00\x00\x00\x00",
    "/home/user/raw_data/dir2/data.wal": b"\x37\x7F\x06\x82\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03",
    "/home/user/raw_data/dir1/dir2/print.gcode": b"; FLAVOR:Marlin\nG0 X10 Y10 Z10\nG1 X20 Y20 E5\n",
    "/home/user/raw_data/dir1/ignore.txt": b"This is just a random text file"
}
for p, c in files.items():
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(c)
'

    chown -R user:user /home/user/raw_data
    chown -R user:user /home/user/categorized
    chmod -R 777 /home/user
