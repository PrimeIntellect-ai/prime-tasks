#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import os

def setup():
    os.makedirs('/home/user', exist_ok=True)
    random.seed(42)
    seq = ""
    # 20 blocks of 500, total 10000 bases
    gc_probs = [0.4, 0.4, 0.4, 0.8, 0.8, 0.2, 0.2, 0.5, 0.5, 0.5, 0.9, 0.9, 0.4, 0.4, 0.6, 0.6, 0.3, 0.3, 0.5, 0.5]
    for p in gc_probs:
        for _ in range(500):
            if random.random() < p:
                seq += random.choice(['G', 'C'])
            else:
                seq += random.choice(['A', 'T'])

    with open('/home/user/input.fasta', 'w') as f:
        f.write(">synthetic_seq\n")
        for i in range(0, len(seq), 80):
            f.write(seq[i:i+80] + "\n")

if __name__ == "__main__":
    setup()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
