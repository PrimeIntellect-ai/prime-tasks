#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts/dirA/dirB
    mkdir -p /home/user/artifacts/dirC
    mkdir -p /home/user/backup_dest/dirA
    mkdir -p /home/user/backup_dest/dirC

    cat << 'EOF' > /tmp/setup.py
import struct
import os

def make_artf(path, version):
    with open(path, 'wb') as f:
        f.write(b'ARTF')
        f.write(struct.pack('<I', version))
        f.write(b'data')

make_artf('/home/user/artifacts/root_file.bin', 2)
make_artf('/home/user/backup_dest/root_file.bin', 2)

make_artf('/home/user/artifacts/dirA/file_a.bin', 5)
make_artf('/home/user/backup_dest/dirA/file_a.bin', 3)

make_artf('/home/user/artifacts/dirA/dirB/file_b.bin', 1)

make_artf('/home/user/artifacts/dirC/file_c.bin', 4)
make_artf('/home/user/backup_dest/dirC/file_c.bin', 6)

with open('/home/user/artifacts/invalid.bin', 'wb') as f:
    f.write(b'BADF\x01\x00\x00\x00data')
EOF

    python3 /tmp/setup.py

    ln -s /home/user/artifacts/dirA /home/user/artifacts/dirC/link_to_A
    ln -s /home/user/artifacts /home/user/artifacts/dirA/link_to_root

    cat << 'EOF' > /home/user/backup.py
import os
import shutil

src = '/home/user/artifacts'
dst = '/home/user/backup_dest'

for root, dirs, files in os.walk(src, followlinks=True):
    for f in files:
        if f.endswith('.bin'):
            src_path = os.path.join(root, f)
            rel_path = os.path.relpath(src_path, src)
            dst_path = os.path.join(dst, rel_path)

            # Dumb logic
            if not os.path.exists(dst_path):
                os.makedirs(os.path.dirname(dst_path), exist_ok=True)
                shutil.copy2(src_path, dst_path)
EOF

    chmod -R 777 /home/user
