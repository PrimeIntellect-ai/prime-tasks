#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy setuptools

    mkdir -p /app/py_kmer_counter-1.0/py_kmer_counter

    cat << 'EOF' > /app/py_kmer_counter-1.0/setup.py
from stuptools import setup

setup(
    name='py_kmer_counter',
    version='1.0',
    packages=['py_kmer_counter'],
)
EOF

    cat << 'EOF' > /app/py_kmer_counter-1.0/py_kmer_counter/__init__.py
def count_3mers(seq):
    from itertools import product
    kmers = [''.join(p) for p in product('ACGT', repeat=3)]
    counts = {k: 0 for k in kmers}
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        if kmer in counts:
            counts[kmer] += 1
    return counts
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/solve_oracle.py
import sys
import numpy as np

def solve():
    seq = sys.stdin.read().strip()
    if not seq:
        return
    from itertools import product
    kmers = [''.join(p) for p in product('ACGT', repeat=3)]
    counts = {k: 0 for k in kmers}
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        if kmer in counts:
            counts[kmer] += 1

    matrix = np.zeros(64)
    for i, k in enumerate(kmers):
        matrix[i] = counts[k]
    matrix = matrix.reshape((8, 8))

    _, S, _ = np.linalg.svd(matrix)
    largest_sv = S[0]
    print(f"{largest_sv:.4f}")

if __name__ == '__main__':
    solve()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
