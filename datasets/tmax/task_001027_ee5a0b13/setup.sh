#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy biopython

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.txt
ATGCGTACGTAGCTAGCTAGCTAG
CGATCGACTGACTAGCTAGCTAGC
GGGGGGGGGGGGGGGGGGGGGGGG
ATATATATATATATATATATATAT
EOF

    cat << 'EOF' > /home/user/generate_features.py
import numpy as np
import pandas as pd
from Bio import pairwise2
import sys

def calculate_gc_content(seq, t):
    idx = int(t)
    if idx >= len(seq): 
        idx = len(seq) - 1
    return 1.0 if seq[idx] in 'GC' else 0.0

def integrate_feature(seq):
    L = len(seq)
    dt = 0.5 
    y = 0.0
    for t in np.arange(0, L, dt):
        dydt = 100 * (calculate_gc_content(seq, t) - y)
        y += dydt * dt
    return y

def matrix_feature(seq):
    mapping = {'A':0, 'C':1, 'G':2, 'T':3}
    encoded = np.zeros((len(seq), 4))
    for i, base in enumerate(seq):
        encoded[i, mapping[base]] = 1.0
    U, S, Vh = np.linalg.svd(encoded)
    return S[0]

def primer_alignment(seq):
    primer = "GCATCGATCG"
    alignments = pairwise2.align.localxx(seq, primer)
    if alignments:
        return alignments[0].score
    return 0.0

def main():
    with open('/home/user/sequences.txt', 'r') as f:
        sequences = [line.strip() for line in f if line.strip()]

    results = []
    for seq in sequences:
        y_val = integrate_feature(seq)
        svd_val = matrix_feature(seq)
        align_val = primer_alignment(seq)
        results.append({
            'Sequence': seq,
            'Integration': round(y_val, 4),
            'SVD': round(svd_val, 4),
            'Alignment': align_val
        })

    df = pd.DataFrame(results)
    df.to_csv('/home/user/training_features.csv', index=False)

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
