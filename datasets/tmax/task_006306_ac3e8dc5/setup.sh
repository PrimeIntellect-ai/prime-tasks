#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    # Generate structure.pdb
    cat << 'EOF' > /tmp/generate_pdb.py
import os
import math

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/structure.pdb', 'w') as f:
    for i in range(1, 51):
        x = 2.0 * i
        y = 5.0 * math.sin(i)
        z = 5.0 * math.cos(i)
        f.write(f"ATOM  {i:4d}  CA  ALA A {i:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C\n")
EOF
    python3 /tmp/generate_pdb.py
    rm /tmp/generate_pdb.py

    chmod -R 777 /home/user
