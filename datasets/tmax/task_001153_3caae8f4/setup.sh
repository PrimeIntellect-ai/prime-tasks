#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_fasta.py
import random

random.seed(42)

aas = ['A', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L', 
       'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'V', 'W', 'Y']

probs = [0.1] + [(0.9 / 19)] * 19

with open('/home/user/sequences.fasta', 'w') as f:
    for i in range(2000):
        f.write(f">seq_{i}\n")
        seq = "".join(random.choices(aas, weights=probs, k=50))
        f.write(f"{seq}\n")
EOF

    python3 /tmp/generate_fasta.py
    rm /tmp/generate_fasta.py

    chmod -R 777 /home/user
