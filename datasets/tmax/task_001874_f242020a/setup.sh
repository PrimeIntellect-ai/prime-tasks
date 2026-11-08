#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import json
import gzip
import bz2

# Define paths
base_dir = "/home/user"
backup_dir = os.path.join(base_dir, "wal_backups")
config_path = os.path.join(base_dir, "backup_config.json")

# Create directories
os.makedirs(backup_dir, exist_ok=True)
os.makedirs(os.path.join(backup_dir, "subdir"), exist_ok=True)

# Headers
valid_magic = b"PG_WAL\x00\x01"
invalid_magic = b"PG_WAL\x00\x00"

# Files to create
files_to_create = [
    ("00000001.wal", valid_magic, False), # match
    ("00000002.wal.gz", valid_magic, "gzip"), # match
    ("00000003.wal.bz2", invalid_magic, "bz2"), # mismatch
    ("subdir/00000004.wal", invalid_magic, False), # mismatch
    ("subdir/00000005.wal.gz", valid_magic, "gzip"), # match
    ("00000006.wal", valid_magic, False), # match
]

for filename, magic, compression in files_to_create:
    filepath = os.path.join(backup_dir, filename)
    data = magic + os.urandom(1024) # Pad with some random bytes

    if compression == "gzip":
        with gzip.open(filepath, 'wb') as f:
            f.write(data)
    elif compression == "bz2":
        with bz2.open(filepath, 'wb') as f:
            f.write(data)
    else:
        with open(filepath, 'wb') as f:
            f.write(data)

# Create config
config_data = {
    "target_magic": "PG_WAL\\x00\\x01",
    "output_archive": "/home/user/verified_wals.tar.gz"
}
with open(config_path, 'w') as f:
    json.dump(config_data, f)
EOF

    # Run setup script
    python3 /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
