#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create setup script for data generation
    cat << 'EOF' > /tmp/setup.py
import os
import struct
import random

# Create directories
os.makedirs("/home/user/artifacts", exist_ok=True)

# Data generation
artifacts = {
    "CORE_SYS_V1": ["CONF_TIMEOUT=30", "CONF_PORT=8080"], # Final: Active
    "DB_DRIVER_X": ["CONF_MAX_CONN=100", "CONF_RETRY=3"], # Final: Removed
    "CACHE_MEM_2": ["CONF_SIZE=1024", "CONF_EVICT=1"],    # Final: Active
    "LEGACY_AUTH": ["CONF_ALLOW_GUEST=0"],                # Final: Removed
    "NET_PROXY_1": ["CONF_BANDWIDTH=5000"]                # Final: Active
}

# Operations sequence (WAL)
# 1 = ADD, 0 = REMOVE
operations = [
    (1, "CORE_SYS_V1"),
    (1, "DB_DRIVER_X"),
    (1, "CACHE_MEM_2"),
    (0, "DB_DRIVER_X"), # Revoke DB
    (1, "LEGACY_AUTH"),
    (0, "CORE_SYS_V1"), # Revoke Core (temp)
    (1, "NET_PROXY_1"),
    (1, "CORE_SYS_V1"), # Re-add Core
    (0, "LEGACY_AUTH")  # Revoke Legacy
]

# Write WAL
with open("/home/user/repo_state.wal", "wb") as f:
    f.write(b"ARTL")
    for op, art_id in operations:
        f.write(struct.pack("B", op))
        f.write(struct.pack("B", len(art_id)))
        f.write(art_id.encode("ascii"))

# Write Artifact Binaries
for art_id, configs in artifacts.items():
    with open(f"/home/user/artifacts/{art_id}.bin", "wb") as f:
        # write random binary junk
        f.write(os.urandom(128))
        for conf in configs:
            f.write(conf.encode("ascii"))
            f.write(os.urandom(64)) # More junk between strings
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
