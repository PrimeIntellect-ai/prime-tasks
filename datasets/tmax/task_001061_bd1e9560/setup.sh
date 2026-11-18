#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/analysis

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/analysis', exist_ok=True)

random.seed(42)
with open('/home/user/data/input.fasta', 'w') as f:
    for i in range(10000):
        # 10% chance for Group A
        if random.random() < 0.1:
            # Group A has higher GC content (~60%)
            seq = "".join(random.choices(['A','C','G','T'], weights=[0.2, 0.3, 0.3, 0.2], k=150)) + "ATGCATGC" + "".join(random.choices(['A','C','G','T'], weights=[0.2, 0.3, 0.3, 0.2], k=150))
        else:
            # Group B has lower GC content (~40%)
            seq = "".join(random.choices(['A','C','G','T'], weights=[0.3, 0.2, 0.2, 0.3], k=308))

        # occasionally inject the motif randomly into Group B so it becomes Group A (but with lower GC)
        if random.random() < 0.05:
             seq = seq[:100] + "ATGCATGC" + seq[108:]

        f.write(f">seq_{i}\n{seq}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
