#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create setup script and run it
    cat << 'EOF' > /tmp/setup.py
import os
import struct

def setup_task():
    base_dir = "/home/user/cfg_manager"
    raw_dir = os.path.join(base_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)

    # Create archive 1
    data1 = [
        (b"alpha.conf", b"loglevel=info\ndb_host=legacy-db.local\nmax_conns=100\n"),
        (b"beta.conf", b"timeout=30\ndb_host=legacy-db.local\n"),
        (b"alpha.conf", b"loglevel=debug\ndb_host=wrong.local\nmax_conns=999\n"),
        (b"gamma.conf", b"enable_feature_x=true\n")
    ]

    with open(os.path.join(raw_dir, "backup_cfg_01.dat"), "wb") as f:
        f.write(b"CFGPAK01")
        f.write(struct.pack("<I", len(data1)))
        for name, content in data1:
            name_padded = name.ljust(64, b'\0')
            f.write(name_padded)
            f.write(struct.pack("<I", len(content)))
            f.write(content)

    # Create archive 2
    data2 = [
        (b"delta.conf", b"cache_size=1024\ndb_host=legacy-db.local\n"),
        (b"delta.conf", b"cache_size=2048\ndb_host=bad.local\n"),
    ]

    with open(os.path.join(raw_dir, "backup_cfg_02.dat"), "wb") as f:
        f.write(b"CFGPAK01")
        f.write(struct.pack("<I", len(data2)))
        for name, content in data2:
            name_padded = name.ljust(64, b'\0')
            f.write(name_padded)
            f.write(struct.pack("<I", len(content)))
            f.write(content)

if __name__ == "__main__":
    setup_task()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
