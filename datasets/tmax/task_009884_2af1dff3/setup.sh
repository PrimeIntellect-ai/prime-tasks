#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

base_dir = "/home/user/legacy_configs"
os.makedirs(os.path.join(base_dir, "db_configs"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "network", "switches"), exist_ok=True)

magic_header = b'\x43\x46\x47\x01\x00\x00\x00\x00'

files_to_create = [
    {
        "path": "db_configs/main_db.cfg",
        "valid": True,
        "payload": "host=192.168.1.100\nport=5432\nuser=admin\n"
    },
    {
        "path": "network/switches/core_switch.bin",
        "valid": True,
        "payload": "vlan=10,20\nmtu=1500\nspanning_tree=rstp\n"
    },
    {
        "path": "system_global.dat",
        "valid": True,
        "payload": "debug_mode=false\nlog_level=WARN\n"
    },
    {
        "path": "db_configs/backup_db.cfg",
        "valid": False,
        "payload": "host=192.168.1.101\n",
        "custom_header": b'\x43\x46\x47\x02\x00\x00\x00\x00' 
    },
    {
        "path": "readme.txt",
        "valid": False,
        "payload": "This directory contains legacy configs.",
        "custom_header": b''
    }
]

for f in files_to_create:
    full_path = os.path.join(base_dir, f["path"])
    header = magic_header if f["valid"] else f.get("custom_header", b'')
    encoded_payload = f["payload"].encode('utf-16le')

    with open(full_path, 'wb') as out:
        out.write(header + encoded_payload)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
