#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip gcc g++ make
    pip3 install pytest

    # Setup miniz
    mkdir -p /app/miniz-3.0.2
    cd /app/miniz-3.0.2
    wget -q https://github.com/richgel999/miniz/releases/download/3.0.2/miniz-3.0.2.zip
    unzip -q miniz-3.0.2.zip
    rm miniz-3.0.2.zip

    # Create broken Makefile
    cat << 'EOF' > Makefile
CC=false
AR=echo

libminiz.a: miniz.o
	$(AR) rcs $@ $^

miniz.o: miniz.c
	$(CC) -O2 -c $< -o $@
EOF

    # Generate dataset
    python3 -c "
import os
import random

os.makedirs('/home/user/dataset', exist_ok=True)
for i in range(50):
    with open(f'/home/user/dataset/file_{i}.log', 'w') as f:
        for _ in range(1000):
            f.write(f'[2023-10-01 12:00:00] INFO: This is a repetitive log line {i} to ensure high compressibility.\n')
    with open(f'/home/user/dataset/file_{i}.dat', 'wb') as f:
        f.write(b'MAGICHEADER12345' + os.urandom(1024 - 16))
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /app/miniz-3.0.2
    chmod -R 777 /home/user
