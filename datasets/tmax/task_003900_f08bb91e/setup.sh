#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy gTTS

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate audio file
    gtts-cli "To identify the synthetic decoy structures, extract the 3D coordinates of all Alpha Carbon atoms, that's the CA atoms, in the PDB file. Compute the full pairwise Euclidean distance matrix for these atoms. Next, perform a Singular Value Decomposition on this distance matrix. Take the top fifty singular values, sorted in descending order, and fit them to an exponential decay model: y equals A times e to the power of negative B times x, where x is the rank index from 0 to 49. If the decay constant B is strictly greater than 0.08, the structure is a synthetic decoy and must be rejected." --output /app/lab_notes.mp3

    # Generate PDB files
    cat << 'EOF' > /tmp/gen_pdb.py
import os
import numpy as np

def make_pdb(path, coords):
    with open(path, 'w') as f:
        for i, (x, y, z) in enumerate(coords):
            f.write(f"ATOM  {i+1:4d}  CA  ALA A{i+1:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n")

# Clean: random points in 3D (slow SVD decay, B <= 0.08)
for i in range(3):
    coords = np.random.rand(100, 3) * 50
    make_pdb(f'/app/corpus/clean/clean_{i}.pdb', coords)

# Evil: points mostly on a 1D line with slight noise (fast SVD decay, B > 0.08)
for i in range(3):
    t = np.linspace(0, 50, 100)
    coords = np.column_stack([t, t, t]) + np.random.rand(100, 3) * 0.1
    make_pdb(f'/app/corpus/evil/evil_{i}.pdb', coords)
EOF

    python3 /tmp/gen_pdb.py
    rm /tmp/gen_pdb.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
