#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_fasta.py
import random

random.seed(123)
with open("/home/user/data/sequences.fasta", "w") as f:
    for i in range(500):
        length = random.randint(100, 200)
        seq = "".join(random.choices(["A", "C", "G", "T"], k=length))
        f.write(f">seq_{i}\n{seq}\n")
EOF
    python3 /home/user/data/generate_fasta.py
    rm /home/user/data/generate_fasta.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
