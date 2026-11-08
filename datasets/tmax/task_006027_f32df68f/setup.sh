#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib pandas

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/setup.py
import numpy as np

np.random.seed(42)
bases = np.array(['A', 'C', 'G', 'T'])

seq = ""
# Chunk 0: Random
seq += ''.join(np.random.choice(bases, 1200))
# Chunk 1: Artificial period 3 (CGA mapping to 1,1,0)
seq += ('CGA' * 400)
# Chunk 2: Random
seq += ''.join(np.random.choice(bases, 1200))
# Chunk 3: Random
seq += ''.join(np.random.choice(bases, 1200))

with open('/home/user/input/genome.fasta', 'w') as f:
    f.write(">synthetic_seq\n")
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + "\n")
EOF

    python3 /home/user/input/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
