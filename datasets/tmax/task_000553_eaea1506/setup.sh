#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import struct

base_dir = "/home/user/app_logs"
os.makedirs(os.path.join(base_dir, "server1"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "server2", "deep"), exist_ok=True)

def write_dat(path, status, payload):
    with open(path, "wb") as f:
        f.write(b"LOG\x00")
        f.write(b"\x01")
        f.write(struct.pack("B", status))
        payload_bytes = payload.encode('utf-8')
        f.write(struct.pack("<I", len(payload_bytes)))
        f.write(payload_bytes)

# File 1: Finished, contains DEBUG and IPs
log1 = "INFO: User admin logged in from 192.168.1.100\nDEBUG: Connection latency 45ms\nWARN: Disk space low on 10.0.0.5\nINFO: Backup completed"
write_dat(os.path.join(base_dir, "server1", "auth.dat"), 0, log1)

# File 2: Active, must be skipped
log2 = "INFO: Writing process started\nDEBUG: Allocating buffers"
write_dat(os.path.join(base_dir, "server1", "active.dat"), 1, log2)

# File 3: Finished, deep directory, contains IPs
log3 = "DEBUG: Init DB\nERROR: Failed to bind to 127.0.0.1\nINFO: Retrying..."
write_dat(os.path.join(base_dir, "server2", "deep", "db.dat"), 0, log3)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
