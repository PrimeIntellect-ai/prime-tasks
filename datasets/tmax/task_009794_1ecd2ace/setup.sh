#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 - << 'EOF'
import math

# Generate an artificial PDB file with 128 CA atoms forming a helix
# Number of full turns = 15
N = 128
turns = 15
radius = 5.0
pitch = 1.5

with open('/home/user/helix.pdb', 'w') as f:
    for i in range(N):
        t = i / N * 2 * math.pi * turns
        x = radius * math.cos(t)
        y = radius * math.sin(t)
        z = pitch * t

        # PDB ATOM format: 
        # ATOM  %5d %-4s %3s %1s%4d    %8.3f%8.3f%8.3f%6.2f%6.2f
        f.write(f"ATOM  {i+1:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
EOF

    chmod -R 777 /home/user
