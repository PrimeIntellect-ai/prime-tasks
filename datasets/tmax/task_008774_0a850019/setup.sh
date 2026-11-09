#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy biopython

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_fasta.py
import random
random.seed(42)
bases = ['A', 'C', 'G', 'T']
with open('/home/user/sequences.fasta', 'w') as f:
    for i in range(500):
        seq = "".join(random.choices(bases, k=100))
        f.write(f">seq_{i}\n{seq}\n")
EOF
    python3 /home/user/setup_fasta.py

    chmod -R 777 /home/user
