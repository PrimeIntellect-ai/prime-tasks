#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import random

base_dir = "/home/user/wals"
os.makedirs(base_dir, exist_ok=True)

page_size = 4096
wal_header = struct.pack(">IIIIIIII", 0x377f0682, 3007000, page_size, 0, 0, 0, 0, 0)

for i in range(10):
    filepath = os.path.join(base_dir, f"db_{i}.wal")
    with open(filepath, "wb") as f:
        f.write(wal_header)

        for j in range(50):
            pgno = random.randint(1, 100)
            if i in [2, 6] and j == 25:
                pgno = 999

            frame_header = struct.pack(">IIIIII", pgno, 0, 0, 0, 0, 0)
            f.write(frame_header)
            f.write(os.urandom(page_size))

trigger_script = """import time
import os

target_file = "/home/user/wals/db_7.wal"
while True:
    with open(target_file, "a") as f:
        f.write("junk")
    time.sleep(1)
"""
with open("/home/user/trigger_db.py", "w") as f:
    f.write(trigger_script)
os.chmod("/home/user/trigger_db.py", 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
