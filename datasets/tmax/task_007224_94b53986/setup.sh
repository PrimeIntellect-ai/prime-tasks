#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs("/home/user/wals", exist_ok=True)

def write_wal(path, records):
    with open(path, 'wb') as f:
        f.write(b"CFGWAL01")
        for ts, key, val in records:
            key_bytes = key.encode('ascii')
            val_bytes = val.encode('ascii')
            f.write(struct.pack('<IBH', ts, len(key_bytes), len(val_bytes)))
            f.write(key_bytes)
            f.write(val_bytes)

wal1 = [
    (100, "hostname", "server01"),
    (100, "port", "8080"),
    (100, "timeout", "30"),
    (100, "debug", "true")
]

wal2 = [
    (150, "port", "8081"),
    (160, "retry_count", "5")
]

wal3 = [
    (200, "timeout", ""),      # Delete
    (180, "hostname", "server02"),
    (120, "debug", "false")    # Updated later in time, though in wal3
]

write_wal("/home/user/wals/base.wal", wal1)
write_wal("/home/user/wals/update1.wal", wal2)
write_wal("/home/user/wals/update2.wal", wal3)

# Add a noise file that shouldn't be parsed
with open("/home/user/wals/ignore_me.txt", 'w') as f:
    f.write("This is not a wal file.")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
