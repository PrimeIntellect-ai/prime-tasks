#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate the input PDB file
    python3 -c '
import os
import numpy as np

np.random.seed(42)

# Generate synthetic PDB
N_atoms = 500
coords = np.random.randn(N_atoms, 3) * 5.0 + np.array([10.0, -5.0, 2.0])
# Stretch along one axis to give a clear dominant singular value
rotation = np.array([[0.866025, -0.5, 0], [0.5, 0.866025, 0], [0, 0, 1]])
coords = coords @ rotation
coords[:, 0] *= 3.0 

pdb_path = "/home/user/input.pdb"
with open(pdb_path, "w") as f:
    for i, (x, y, z) in enumerate(coords):
        # Format as standard PDB ATOM record
        f.write(f"ATOM  {i+1:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n")
'

    chmod -R 777 /home/user
