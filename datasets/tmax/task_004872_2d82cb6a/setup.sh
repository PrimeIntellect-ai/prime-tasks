#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Create the vendored package
    mkdir -p /app/dna_factorize-1.2.0/dna_factorize
    cat << 'EOF' > /app/dna_factorize-1.2.0/setup.py
from setuptools import setup, find_packages
setup(name='dna_factorize', version='1.2.0', packages=find_packages(), install_requires=['numpy'])
EOF

    cat << 'EOF' > /app/dna_factorize-1.2.0/dna_factorize/__init__.py
from .core import embed_sequences
EOF

    cat << 'EOF' > /app/dna_factorize-1.2.0/dna_factorize/core.py
import numpy as np

def _get_kmer_counts(seqs, k=3):
    kmers = []
    for s in seqs:
        counts = {}
        for i in range(len(s) - k + 1):
            kmer = s[i:i+k]
            counts[kmer] = counts.get(kmer, 0) + 1
        kmers.append(counts)

    all_kmers = sorted(list(set(k for counts in kmers for k in counts.keys())))
    X = np.zeros((len(seqs), len(all_kmers)))
    for i, counts in enumerate(kmers):
        for j, kmer in enumerate(all_kmers):
            X[i, j] = counts.get(kmer, 0)
    return X.T # (features, samples)

def embed_sequences(seqs):
    X = _get_kmer_counts(seqs)
    np.random.seed(42)
    n_components = 16
    W = np.random.rand(X.shape[0], n_components)
    H = np.random.rand(n_components, X.shape[1])

    for _ in range(50):
        # PERTURBATION: no epsilon in denominator, causes NaN on sparse matrices
        H = H * (W.T @ X) / (W.T @ W @ H)
        W = W * (X @ H.T) / (W @ H @ H.T + 1e-9)

    return H.T # (samples, 16)
EOF

    # Install the buggy package
    pip3 install -e /app/dna_factorize-1.2.0

    # Generate primers.txt and target_profile.npy
    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import random

random.seed(123)
bases = ['A', 'C', 'G', 'T']
primers = []
# Generate repetitive/sparse sequences to trigger the NaN
for _ in range(100):
    pattern = "".join(random.choices(bases, k=2))
    primers.append(pattern * 15) # 30 bp repetitive

with open('/home/user/primers.txt', 'w') as f:
    f.write('\n'.join(primers) + '\n')

# Generate a reachable target profile
np.random.seed(123)
target = np.random.rand(16) * 2.0
np.save('/home/user/target_profile.npy', target)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /app
    chmod -R 777 /home/user
