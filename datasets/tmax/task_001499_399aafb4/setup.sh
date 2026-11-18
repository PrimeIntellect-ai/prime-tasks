#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_fasta.py
import os
import numpy as np

np.random.seed(42)
bases = ['A', 'C', 'G', 'T']
seq_list = []
for i in range(1500):
    if i % 3 == 0:
        seq_list.append(np.random.choice(bases, p=[0.7, 0.1, 0.1, 0.1]))
    else:
        seq_list.append(np.random.choice(bases))

sequence = "".join(seq_list)

with open('/home/user/sequence.fasta', 'w') as f:
    f.write(">synth_seq_001\n")
    for i in range(0, len(sequence), 80):
        f.write(sequence[i:i+80] + "\n")
EOF

    python3 /tmp/generate_fasta.py

    chmod -R 777 /home/user
