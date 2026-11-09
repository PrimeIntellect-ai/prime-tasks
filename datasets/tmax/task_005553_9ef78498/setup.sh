#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip file tar gzip coreutils gawk sed grep
    pip3 install pytest

    mkdir -p /home/user/backups/raw
    mkdir -p /home/user/backups/processed
    cd /home/user/backups/raw

    cat << 'EOF' > /home/user/make_elf.py
import sys

def make_elf(filename, bits):
    magic = b'\x7fELF'
    cls = b'\x01' if bits == 32 else b'\x02'
    endian = b'\x01' # Little Endian
    version = b'\x01'
    pad = b'\x00' * 8
    e_ident = magic + cls + endian + version + b'\x00' + pad

    with open(filename, 'wb') as f:
        f.write(e_ident)
        f.write(b'\x00' * 64)

make_elf('dump1.elf', 64)
make_elf('crash2.elf', 32)
EOF
    python3 /home/user/make_elf.py

    echo "TXN: 10452\nLOGDATA\n0x00AABB" > data1.wal
    echo "TXN: 9912\nLOGDATA\n0x00CCDD" > sys2.wal

    zip inner1.zip data1.wal dump1.elf
    zip inner2.zip sys2.wal crash2.elf

    tar -cf db_node_A.tar inner1.zip
    tar -cf db_node_B.tar inner2.zip

    rm -f data1.wal dump1.elf sys2.wal crash2.elf inner1.zip inner2.zip /home/user/make_elf.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
