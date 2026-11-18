#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/setup.py
import h5py
import numpy as np
import random

random.seed(42)
seqs = []
primer = "ATGCGATC"
for i in range(10000):
    length = random.randint(100, 200)
    seq = "".join(random.choices("ACGT", k=length))
    # 15% chance to forcibly include the primer
    if random.random() < 0.15:
        pos = random.randint(0, length - len(primer))
        seq = seq[:pos] + primer + seq[pos+len(primer):]
    seqs.append(seq.encode('ascii'))

with h5py.File('/home/user/data/seqs.h5', 'w') as f:
    f.create_dataset('sequences', data=np.array(seqs, dtype='S'))
EOF
    python3 /home/user/data/setup.py

    chmod -R 777 /home/user
