#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/archives/set1
    mkdir -p /home/user/archives/set2/deep
    mkdir -p /home/user/extracted

    cat << 'EOF' > /home/user/backup_config.toml
source_dir = "/home/user/archives"
target_dir = "/home/user/extracted"
EOF

    cat << 'EOF' > /home/user/make_wal.py
import struct
import os

def write_entry(f, path, data):
    path_bytes = path.encode('utf-8')
    data_bytes = data.encode('utf-8')
    f.write(struct.pack('<H', len(path_bytes)))
    f.write(path_bytes)
    f.write(struct.pack('<I', len(data_bytes)))
    f.write(data_bytes)

with open('/home/user/archives/set1/data1.wal', 'wb') as f:
    write_entry(f, 'safe_file.txt', 'This is safe data.')
    write_entry(f, '../../../../../home/user/hacked.txt', 'This is malicious!')
    write_entry(f, 'nested/dir/safe2.txt', 'More safe data.')

with open('/home/user/archives/set2/deep/data2.wal', 'wb') as f:
    write_entry(f, '/etc/passwd', 'fake root entry')
    write_entry(f, '../extracted/safe3.txt', 'Sneaky but technically safe if resolved strictly.')
    write_entry(f, 'absolute_trick/../../../../../../tmp/pwn', 'Another malicious one.')
EOF

    python3 /home/user/make_wal.py
    rm /home/user/make_wal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
