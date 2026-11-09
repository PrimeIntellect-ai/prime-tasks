#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_dump

    python3 -c '
import os
os.makedirs("/home/user/project_dump", exist_ok=True)

def write_file(name, magic, size_mb, extra=b""):
    path = f"/home/user/project_dump/{name}"
    with open(path, "wb") as f:
        f.write(magic)
        f.write(extra)
        if size_mb > 0:
            f.write(os.urandom(size_mb * 1024 * 1024))

write_file("asset_01.bin", b"\x89\x50\x4E\x47", 10, b"\x00\x01\x02\x03")
write_file("asset_03.bin", b"\x89\x50\x4E\x47", 5, b"\x04\x05\x06\x07")
write_file("data_01.dat", b"\xDA\x7A\xBE\xEF", 2, b"\xAA\xBB\xCC\xDD")
write_file("data_02.dat", b"\xDA\x7A\xBE\xEF", 1, b"\x11\x22\x33\x44")

with open("/home/user/project_dump/sys_01.log", "wb") as f:
    f.write(b"ERR Connection timeout on port 8080\n")
with open("/home/user/project_dump/sys_02.log", "wb") as f:
    f.write(b"ERR Disk space low on /dev/sda1\n")
'

    cp /home/user/project_dump/asset_01.bin /home/user/project_dump/asset_02.bin
    cp /home/user/project_dump/data_01.dat /home/user/project_dump/data_03.dat
    cp /home/user/project_dump/sys_01.log /home/user/project_dump/sys_03.log

    chown -R user:user /home/user/project_dump
    chmod -R 777 /home/user
