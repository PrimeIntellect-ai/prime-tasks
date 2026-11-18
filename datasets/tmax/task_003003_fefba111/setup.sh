#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    # Create directories and run python script to generate RLE files
    cat << 'EOF' > /tmp/setup.py
import os
import struct

base_dir = "/home/user/storage_logs"
os.makedirs(os.path.join(base_dir, "db_tier"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "app_tier/instances"), exist_ok=True)

def write_rle(filepath, text):
    with open(filepath, "wb") as f:
        for char in text:
            f.write(struct.pack('BB', 1, ord(char)))

write_rle(f"{base_dir}/db_tier/db_01.rle", "INFO: Database started\nINFO: Disk usage 40%\nCRITICAL_OOM: postgresql process terminated\nINFO: Restarting\n")
write_rle(f"{base_dir}/app_tier/instances/app_14.rle", "WARN: High latency\nCRITICAL_OOM: worker thread out of memory\nINFO: Handled gracefully\n")
write_rle(f"{base_dir}/app_tier/app_01.rle", "INFO: App started\nINFO: All systems green\n")
write_rle(f"{base_dir}/db_tier/db_02.rle", "CRITICAL_OOM: redis cache memory limit exceeded\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
