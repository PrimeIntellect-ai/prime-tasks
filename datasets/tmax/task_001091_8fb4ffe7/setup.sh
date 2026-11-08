#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ln -s /opt/rust/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Create initial state
    cat << 'EOF' > /tmp/setup.py
import os
import struct

base_dir = "/home/user"
backups_dir = os.path.join(base_dir, "backups")
os.makedirs(backups_dir, exist_ok=True)

# inventory.csv
csv_path = os.path.join(base_dir, "inventory.csv")
with open(csv_path, "w") as f:
    f.write("original_filename,retention_days\n")
    f.write("database_prod.db,90\n")
    f.write("user_uploads.tar,15\n")
    f.write("system_configs.xml,365\n")

# BKP files generation
files_data = [
    ("data_A.bkp", "database_prod.db", 1700000000),
    ("data_B.bkp", "user_uploads.tar", 1701000000),
    ("data_C.bkp", "system_configs.xml", 1702000000),
    ("data_D.bkp", "unknown_logs.txt", 1703000000), # Not in CSV, default 30 days
]

for archive_name, orig_name, ts in files_data:
    filepath = os.path.join(backups_dir, archive_name)
    with open(filepath, "wb") as f:
        # Magic bytes
        f.write(b"BKP1")
        # Timestamp (u64 little endian)
        f.write(struct.pack("<Q", ts))
        # Filename length (u16 little endian)
        orig_bytes = orig_name.encode("utf-8")
        f.write(struct.pack("<H", len(orig_bytes)))
        # Original filename
        f.write(orig_bytes)
        # Dummy payload
        f.write(b"\x00" * 1024 * 10) # 10KB of dummy payload to simulate archive
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /opt/rust
    chmod -R 777 /home/user
