#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_pdb.py
import random
import os

os.makedirs("/home/user", exist_ok=True)
random.seed(42)
with open("/home/user/data.pdb", "w") as f:
    for i in range(1, 100001):
        x = random.uniform(-50, 50)
        y = random.uniform(-50, 50)
        # Induce a statistically significant difference in Z based on X domain
        z = random.uniform(-10, 10) + (0.05 if x >= 0 else 0)
        # PDB ATOM format: 
        # ATOM  %5d %-4s %3s %1s%4d    %8.3f%8.3f%8.3f
        f.write(f"ATOM  {i:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
EOF

    python3 /tmp/generate_pdb.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
