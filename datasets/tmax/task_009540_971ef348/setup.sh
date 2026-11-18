#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/project_dump/dir1/subdirA", exist_ok=True)
os.makedirs("/home/user/project_dump/dir2/subdirB", exist_ok=True)
os.makedirs("/home/user/organized/elf64", exist_ok=True)
os.makedirs("/home/user/organized/wal", exist_ok=True)

with open("/home/user/project_dump/dir1/file_a.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x02\x01\x01\x00\n dummy data 1\n")

with open("/home/user/project_dump/dir2/subdirB/file_b.elf", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x01\x01\x01\x00\n dummy data 2\n")

with open("/home/user/project_dump/dir1/subdirA/data.log", "wb") as f:
    f.write(b"WAL_v3\x00\x11\x22\n wal records\n")

with open("/home/user/project_dump/dir2/old_data.wal", "wb") as f:
    f.write(b"WAL_v2\x00\x11\x22\n")

with open("/home/user/project_dump/dir2/.hidden_elf", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x02\x02\x02\x00\n dummy data 3\n")
'

    chown -R user:user /home/user/project_dump /home/user/organized
    chmod -R 777 /home/user
