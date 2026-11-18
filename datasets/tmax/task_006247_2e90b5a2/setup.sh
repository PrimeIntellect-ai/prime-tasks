#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter nbconvert numpy scipy biopython

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_fasta.py
import numpy as np

np.random.seed(42)
bases = ['A', 'C', 'G', 'T']
with open('/home/user/sequences.fasta', 'w') as f:
    for i in range(25):
        # Group A leans slightly towards A/T
        seq = ''.join(np.random.choice(bases, size=100, p=[0.3, 0.2, 0.2, 0.3]))
        f.write(f">GroupA_seq{i+1}\n{seq}\n")
    for i in range(25):
        # Group B leans slightly towards G/C
        seq = ''.join(np.random.choice(bases, size=100, p=[0.2, 0.3, 0.3, 0.2]))
        f.write(f">GroupB_seq{i+1}\n{seq}\n")
EOF

    python3 /home/user/generate_fasta.py
    rm /home/user/generate_fasta.py

    chmod -R 777 /home/user
