#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_pdb.py
import random
import os

os.makedirs("/home/user", exist_ok=True)
random.seed(42)

with open("/home/user/structure.pdb", "w") as f:
    for i in range(1, 10001):
        atom_types = ['CA', 'CB', 'N', 'O']
        atype = random.choice(atom_types)
        if atype == 'CA': 
            bfac = random.gauss(20.0, 5.0)
        elif atype == 'CB': 
            bfac = random.gauss(22.0, 6.0)
        else: 
            bfac = random.gauss(15.0, 3.0)

        # Format B-factor into a string first to simulate standard PDB
        # B-factor fits in columns 61-66
        bfac_str = f"{bfac:6.2f}"

        line = f"ATOM  {i:5d} {atype:<4s} ALA A   1      10.000  10.000  10.000  1.00{bfac_str}\n"
        f.write(line)
EOF

    python3 /tmp/gen_pdb.py
    rm /tmp/gen_pdb.py

    chmod -R 777 /home/user
