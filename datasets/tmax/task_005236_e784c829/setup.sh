#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /app/seqtools
    cat << 'EOF' > /app/seqtools/__init__.py
from .scorer import score_profile
EOF

    cat << 'EOF' > /app/seqtools/scorer.py
import numpy as np

# BUG: Missing the 4th row
WEIGHT_MATRIX = np.array([
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0]
])

def score_profile(seq: str) -> np.ndarray:
    mapping = {'A': [1,0,0,0], 'C': [0,1,0,0], 'G': [0,0,1,0], 'T': [0,0,0,1]}
    vectors = [mapping.get(c, [0,0,0,0]) for c in seq.upper()]
    mat = np.array(vectors)
    # The dot product will fail if WEIGHT_MATRIX is 3x4 and mat is Nx4
    scores = np.dot(mat, WEIGHT_MATRIX.T)
    # Return row sums as arbitrary score
    return np.sum(scores, axis=1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
