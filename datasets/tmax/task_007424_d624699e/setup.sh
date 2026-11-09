#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

fasta_path = '/home/user/dataset.fasta'
os.makedirs('/home/user', exist_ok=True)

with open(fasta_path, 'w') as f:
    # Generate 9990 sequences with exactly 50% GC
    seq_50 = 'G' * 50 + 'A' * 50
    for i in range(9990):
        f.write(f">seq_{i}\n{seq_50}\n")

    # Generate 10 sequences with exactly 51% GC
    seq_51 = 'G' * 51 + 'A' * 49
    for i in range(9990, 10000):
        f.write(f">seq_{i}\n{seq_51}\n")

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
