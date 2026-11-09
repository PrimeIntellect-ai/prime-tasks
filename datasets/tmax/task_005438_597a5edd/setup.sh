#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev pkg-config cargo rustc
    pip3 install pytest h5py numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np
import os
import subprocess

# 1. Create HDF5 Data
np.random.seed(42)
probs = np.random.uniform(0.1, 0.3, (4, 10000))
# Inject a GC-rich region to ensure a specific 500bp window wins the density estimation
probs[1:3, 4000:4500] += 0.4 # Boost C and G probabilities

# Inject the ideal motif within the 500bp window (e.g., at index 4200)
ideal = "GCGCATATGCGCATATGCGC"
nuc_map = {'A':0, 'C':1, 'G':2, 'T':3}
for i, char in enumerate(ideal):
    probs[:, 4200+i] = 0.01
    probs[nuc_map[char], 4200+i] = 0.9

# Normalize
probs = probs / probs.sum(axis=0, keepdims=True)

with h5py.File('/app/genomic_landscape.h5', 'w') as f:
    f.create_dataset('nucleotide_probs', data=probs, dtype='float32')

# 2. Create the stripped binary C code
c_code = """
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *seq = argv[1];
    if (strlen(seq) != 20) return 1;

    char *ideal = "GCGCATATGCGCATATGCGC";
    float score = 0.0;

    for (int i = 0; i < 20; i++) {
        if (seq[i] == ideal[i]) score += 4.0;
        if (seq[i] == 'G' || seq[i] == 'C') score += 1.0;
    }

    printf("%.2f\\n", score);
    return 0;
}
"""
with open('/tmp/scorer.c', 'w') as f:
    f.write(c_code)

subprocess.run(["gcc", "-O2", "/tmp/scorer.c", "-o", "/app/binding_scorer"], check=True)
subprocess.run(["strip", "/app/binding_scorer"], check=True)
os.remove("/tmp/scorer.c")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
