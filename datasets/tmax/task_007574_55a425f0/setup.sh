#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_fasta.py
import random
random.seed(42)
with open("/home/user/input.fasta", "w") as f:
    for i in range(1000):
        length = int(random.gauss(500, 100))
        if length < 50: length = 50
        f.write(f">seq_{i}\n")
        seq = "".join(random.choices("ACGT", k=length))
        for j in range(0, length, 80):
            f.write(seq[j:j+80] + "\n")
EOF

    python3 /home/user/generate_fasta.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
