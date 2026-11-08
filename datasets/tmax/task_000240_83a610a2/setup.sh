#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_pdb.py
import os
import numpy as np

np.random.seed(123)

n_residues = 200
residues = ['ALA', 'GLY', 'VAL', 'LEU', 'ILE', 'PRO']

pdb_lines = []
for i in range(1, n_residues + 1):
    res_name = np.random.choice(residues, p=[0.3, 0.2, 0.15, 0.15, 0.1, 0.1])
    if i == 1:
        coord = np.array([0.0, 0.0, 0.0])
    else:
        coord += np.random.randn(3) * 3.8 

    line = f"ATOM  {i:>5}  CA  {res_name:<3} A{i:>4}    {coord[0]:8.3f}{coord[1]:8.3f}{coord[2]:8.3f}  1.00 20.00           C  "
    pdb_lines.append(line)

with open("/home/user/protein.pdb", "w") as f:
    f.write("\n".join(pdb_lines) + "\n")
EOF

    python3 /tmp/generate_pdb.py
    rm /tmp/generate_pdb.py

    chmod -R 777 /home/user
