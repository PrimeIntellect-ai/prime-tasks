#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make file libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/bin_backup", exist_ok=True)
os.makedirs("/home/user/bin_archive", exist_ok=True)

with open("/home/user/bin_backup/serviceA.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x02\x01\x01\x00")

with open("/home/user/bin_backup/serviceB.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x02\x01\x01\x00")

with open("/home/user/bin_backup/legacy_worker.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x01\x01\x01\x00")

with open("/home/user/bin_backup/blob_data.bin", "wb") as f:
    f.write(b"\x00\x00\x00\x00\x00\x00\x00\x00")

with open("/home/user/bin_backup/readme.txt", "wb") as f:
    f.write("Archiving requires attention to detail.".encode("utf-16le"))
'

    chown -R user:user /home/user/bin_backup /home/user/bin_archive
    chmod -R 777 /home/user
