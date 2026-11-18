#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/subdir1/subdir2
    mkdir -p /home/user/dataset/subdir3
    mkdir -p /home/user/wal_parser

    cat << 'EOF' > /home/user/config.ini
[dataset]
extension=wal
magic=DEADBEEF
EOF

    cat << 'EOF' > /tmp/gen_wal.py
import struct

def write_wal(path, valid_counts, inject_garbage=False):
    with open(path, 'wb') as f:
        for _ in range(valid_counts):
            f.write(bytes.fromhex('DEADBEEF'))
            f.write(b'\x00' * 12)
        if inject_garbage:
            f.write(b'garbage123')
            f.write(bytes.fromhex('DEADBEEF'))
            f.write(b'\x01' * 12)

write_wal('/home/user/dataset/file_a.wal', 4)
write_wal('/home/user/dataset/subdir1/file_b.wal', 12, True)
write_wal('/home/user/dataset/subdir3/file_c.wal', 0)
write_wal('/home/user/dataset/subdir1/subdir2/file_d.wal', 1)

# File with wrong extension
write_wal('/home/user/dataset/subdir1/ignore.dat', 10)
EOF

    python3 /tmp/gen_wal.py

    ln -s /home/user/dataset /home/user/dataset/subdir3/loop_to_root
    ln -s /home/user/dataset/subdir1 /home/user/dataset/subdir1/subdir2/loop_to_subdir1

    chown -R user:user /home/user
    chmod -R 777 /home/user
