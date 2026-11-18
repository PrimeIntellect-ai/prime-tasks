#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create data directory and files using Python for exact byte control
    python3 -c '
import os
import time

data_dir = "/home/user/data"
os.makedirs(data_dir, exist_ok=True)

files = [
    ("file1.arc", 15360, b"\xDE\xAD\xBE\xEF\x00\x00\x00\x01", 2),
    ("file2.arc", 12288, b"\xCA\xFE\xBA\xBE\x00\x00\x00\x02", 1),
    ("file3.arc", 5120, b"\x11\x22\x33\x44\x55\x66\x77\x88", 1),
    ("file4.arc", 20480, b"\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11", 10),
    ("file5.txt", 15361, b"Hello World", 1),
]

now = time.time()
day = 24 * 3600

for filename, size, prefix, days_ago in files:
    filepath = os.path.join(data_dir, filename)
    with open(filepath, "wb") as f:
        f.write(prefix)
        f.write(b"\x00" * (size - len(prefix)))
    mtime = now - (days_ago * day)
    os.utime(filepath, (mtime, mtime))
'

    chmod -R 777 /home/user
