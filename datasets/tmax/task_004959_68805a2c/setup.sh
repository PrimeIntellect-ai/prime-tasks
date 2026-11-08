#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile

os.chdir('/home/user')

def create_bin(filename, magic, version, desc):
    with open(filename, 'wb') as f:
        desc_bytes = desc.encode('ascii')
        f.write(struct.pack(f'<4sHH{len(desc_bytes)}s', magic, version, len(desc_bytes), desc_bytes))
        f.write(b'\x00\x01\x02\x03\x04\x05')

create_bin('alpha.bin', b'ARTI', 1, 'Alpha_Component')
create_bin('beta.bin', b'ARTI', 2, 'Beta_Module')
create_bin('gamma.bin', b'ARTI', 1, 'Gamma_Service')
create_bin('delta.bin', b'ARTI', 3, 'Delta_Core')
create_bin('invalid.bin', b'BADD', 1, 'Bad_Magic')

with tarfile.open('batch1.tar', 'w') as tar:
    tar.add('alpha.bin')
    tar.add('beta.bin')
    tar.add('invalid.bin')

with tarfile.open('batch2.tar', 'w') as tar:
    tar.add('gamma.bin')
    tar.add('delta.bin')

with tarfile.open('artifacts.tar.gz', 'w:gz') as tar:
    tar.add('batch1.tar')
    tar.add('batch2.tar')

for f in ['alpha.bin', 'beta.bin', 'gamma.bin', 'delta.bin', 'invalid.bin', 'batch1.tar', 'batch2.tar']:
    os.remove(f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
