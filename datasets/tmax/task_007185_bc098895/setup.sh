#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import gzip

base_dir = "/home/user/config_backups"
os.makedirs(base_dir, exist_ok=True)

def write_ccf(filepath, timestamp, entries, magic=b"CCF1"):
    with open(filepath, "wb") as f:
        # Header
        f.write(struct.pack("<4s I H", magic, timestamp, len(entries)))
        # Entries
        for k, v in entries.items():
            k_bytes = k.encode('utf-8')
            v_bytes = v.encode('utf-8')
            f.write(struct.pack("<H", len(k_bytes)))
            f.write(k_bytes)
            f.write(struct.pack("<I", len(v_bytes)))
            f.write(v_bytes)

def write_ccf_gz(filepath, timestamp, entries, magic=b"CCF1"):
    with gzip.open(filepath, "wb") as f:
        f.write(struct.pack("<4s I H", magic, timestamp, len(entries)))
        for k, v in entries.items():
            k_bytes = k.encode('utf-8')
            v_bytes = v.encode('utf-8')
            f.write(struct.pack("<H", len(k_bytes)))
            f.write(k_bytes)
            f.write(struct.pack("<I", len(v_bytes)))
            f.write(v_bytes)

# Server 1: db-server
os.makedirs(f"{base_dir}/db-server", exist_ok=True)
write_ccf(f"{base_dir}/db-server/backup_old.ccf", 1600000000, {"target_version": "v10.1", "memory": "16G"})
write_ccf_gz(f"{base_dir}/db-server/backup_new.ccf.gz", 1650000000, {"target_version": "v11.4", "memory": "32G"})
write_ccf(f"{base_dir}/db-server/backup_invalid.ccf", 1660000000, {"target_version": "v12.0"}, magic=b"BAD1") # Wrong magic bytes

# Server 2: web-server
os.makedirs(f"{base_dir}/web-server", exist_ok=True)
write_ccf(f"{base_dir}/web-server/state1.ccf", 1640000000, {"port": "80", "target_version": "nginx-1.18"})
write_ccf_gz(f"{base_dir}/web-server/state2.ccf.gz", 1645000000, {"port": "443", "target_version": "nginx-1.20"})

# Corrupt gzip file for web-server
with open(f"{base_dir}/web-server/corrupt.ccf.gz", "wb") as f:
    f.write(b"NOT A GZIP FILE THIS IS CORRUPTED DATA")

# Server 3: cache-server
os.makedirs(f"{base_dir}/cache-server", exist_ok=True)
write_ccf_gz(f"{base_dir}/cache-server/bkp1.ccf.gz", 1610000000, {"target_version": "redis-5.0", "maxmemory": "2gb"})
write_ccf(f"{base_dir}/cache-server/bkp2.ccf", 1615000000, {"target_version": "redis-6.2", "maxmemory": "4gb"})

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/config_backups
    chmod -R 777 /home/user
