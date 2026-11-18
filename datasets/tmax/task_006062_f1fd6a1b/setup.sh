#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/dataset', exist_ok=True)
sigs = ['A1B2C3D4', 'F9E8D7C6', 'ZZ99YY88', 'Q1W2E3R4', 'MNBVCXZA']

for i in range(1, 6):
    filename = f'/home/user/dataset/raw_data_0{i}.dat'
    with open(filename, 'w') as f:
        for j in range(1, 11):
            f.write(f'JUNK HEADER LINE {j}\n')
        for j in range(11, 10001):
            if j == 5000:
                f.write(f'1234567890, 0.00 MAGIC_SIG:{sigs[i-1]} END\n')
            else:
                f.write(f'1234567890, {random.random()}\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
