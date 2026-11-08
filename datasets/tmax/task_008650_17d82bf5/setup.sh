#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

np.random.seed(123)

with open("/home/user/protein.pdb", "w") as f:
    atom_id = 1
    # Create 120 residues
    residues = ["VAL", "ALA", "VAL", "GLY", "VAL", "ALA", "VAL", "ALA", "VAL", "VAL", "ALA", "ALA"] * 10
    for res_id, res_name in enumerate(residues):
        x, y, z = np.random.rand(3) * 50
        bfactor = np.random.rand() * 100
        # PDB format string
        f.write(f"ATOM  {atom_id:5d}  CA  {res_name} A{res_id:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00{bfactor:6.2f}           C\n")
        atom_id += 1
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
