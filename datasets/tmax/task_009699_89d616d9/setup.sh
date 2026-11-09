#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import json

base_dir = "/home/user"
wal_dir = os.path.join(base_dir, "wal_logs")

os.makedirs(wal_dir, exist_ok=True)

# Create config
config_data = {
    "wal_dir": wal_dir,
    "archive_path": os.path.join(base_dir, "backup.tar.gz")
}
with open(os.path.join(base_dir, "backup_config.json"), "w") as f:
    json.dump(config_data, f)

# Helper to pack wal records
def pack_record(rec_type, payload):
    b_payload = payload.encode('utf-8') if isinstance(payload, str) else payload
    length = len(b_payload)
    return struct.pack(f">IB{length}s", length, rec_type, b_payload)

# File 1
with open(os.path.join(wal_dir, "001_tx.wal"), "wb") as f:
    f.write(pack_record(2, b'\x00\x11\x22')) # Data
    f.write(pack_record(1, "MAX_CONNECTIONS=500")) # Config
    f.write(pack_record(2, b'\x33\x44')) # Data
    f.write(pack_record(1, "ENABLE_LOGGING=true")) # Config

# File 2
with open(os.path.join(wal_dir, "002_tx.wal"), "wb") as f:
    f.write(pack_record(1, "CACHE_SIZE=1024MB")) # Config
    f.write(pack_record(2, b'\xff\xff\xff')) # Data
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
