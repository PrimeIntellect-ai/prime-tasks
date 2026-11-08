#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src /home/user/bin /home/user/output

    cat << 'EOF' > /tmp/setup_pdb.py
import random
import math

random.seed(42)
with open('/home/user/data/molecule.pdb', 'w') as f:
    for i in range(1, 10001):
        x = random.uniform(-10, 10)
        y = random.uniform(-10, 10)
        z = random.uniform(-10, 10)
        # PDB ATOM format: 
        # 1-6 "ATOM  ", 7-11 atom serial number, 13-16 atom name, 18-20 residue name, 
        # 22 chain id, 23-26 res seq, 31-38 X, 39-46 Y, 47-54 Z
        f.write(f"ATOM  {i:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
EOF
    python3 /tmp/setup_pdb.py
    rm /tmp/setup_pdb.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
