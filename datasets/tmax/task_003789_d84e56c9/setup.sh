#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/config.json
{"cutoff_time": 1600000000, "backup_dir": "/home/user/backups", "report_file": "/home/user/cleanup_report.txt"}
EOF

    cat << 'EOF' > /tmp/setup_wal.py
import struct
import os

backups = [
    ("backup_1.wal", 1500000000, 0x003E),
    ("backup_2.wal", 1700000000, 0x00B7),
    ("backup_3.wal", 1400000000, 0x0028),
    ("backup_4.wal", 1650000000, 0x003E),
    ("backup_5.wal", 1550000000, 0x00F3)
]

for name, ts, arch in backups:
    path = os.path.join("/home/user/backups", name)
    with open(path, "wb") as f:
        # 1. Magic Bytes
        f.write(b"WALB")
        # 2. Timestamp (Big-Endian uint32)
        f.write(struct.pack(">I", ts))
        # 3. Payload Length (Big-Endian uint32) - simulate 10MB
        payload_len = 10 * 1024 * 1024
        f.write(struct.pack(">I", payload_len))

        # 4. Embedded ELF starts here (Offset 12)
        elf_header = bytearray(b"\x7FELF" + b"\x00" * 14) # 18 bytes
        f.write(elf_header)
        f.write(struct.pack("<H", arch))

        # Write padding to simulate the rest of the large payload
        f.write(b"\x00" * (1024 * 1024))
EOF

    python3 /tmp/setup_wal.py
    rm /tmp/setup_wal.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
