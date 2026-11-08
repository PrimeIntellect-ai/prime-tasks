#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip perl ruby gawk
    pip3 install pytest numpy h5py scipy scikit-learn statsmodels jupyter

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import h5py
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)

N = 50
np.random.seed(42)

signals = np.zeros((N, 512))
fasta_lines = []

bases = ['A', 'C', 'G', 'T']

for i in range(N):
    # Choose a frequency peak
    f = np.random.randint(10, 80)

    # Generate signal
    t = np.arange(512)
    signal = np.sin(2 * np.pi * f * t / 512) + np.random.normal(0, 0.5, 512)
    signals[i] = signal

    # Generate FASTA
    seq = np.random.choice(bases, 300).tolist()

    pos = -1
    if i % 5 != 0:
        pos = 2 * f + 5
        # Insert GATTACA at pos
        seq[pos:pos+7] = list("GATTACA")

    fasta_lines.append(f">seq_{i}")
    fasta_lines.append("".join(seq))

with h5py.File('/home/user/data/signals.h5', 'w') as hf:
    hf.create_dataset('raw_signals', data=signals)

with open('/home/user/data/reads.fasta', 'w') as f:
    f.write("\n".join(fasta_lines) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
