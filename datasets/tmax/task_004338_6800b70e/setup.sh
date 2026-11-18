#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest matplotlib biopython

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_fasta.py
import os
import random

seq_len = 1000
num_seqs = 5
random.seed(42)
baseline = "".join(random.choices("ACGT", k=seq_len))

def force_conservation(seqs, start, end, ratio):
    cols_to_conserve = int((end - start) * ratio)
    conserved_indices = set(random.sample(range(start, end), cols_to_conserve))
    for i in range(start, end):
        if i in conserved_indices:
            for j in range(num_seqs):
                seqs[j][i] = baseline[i]
        else:
            for j in range(num_seqs):
                seqs[j][i] = random.choice("ACGT")
            while len(set(seqs[j][i] for j in range(num_seqs))) == 1:
                seqs[0][i] = random.choice("ACGT")

seqs = [list(baseline) for _ in range(num_seqs)]

force_conservation(seqs, 0, 1000, 0.2)
force_conservation(seqs, 0, 200, 0.72)
force_conservation(seqs, 0, 100, 0.75)
force_conservation(seqs, 50, 100, 0.8)
force_conservation(seqs, 50, 75, 1.0)

force_conservation(seqs, 800, 1000, 0.72)
force_conservation(seqs, 900, 1000, 0.75)
force_conservation(seqs, 900, 950, 0.8)
force_conservation(seqs, 900, 925, 1.0)

with open("/home/user/aligned_sequences.fasta", "w") as f:
    for i in range(num_seqs):
        f.write(f">Seq{i+1}\n")
        f.write("".join(seqs[i]) + "\n")
EOF

    python3 /tmp/generate_fasta.py
    rm /tmp/generate_fasta.py

    chmod -R 777 /home/user
