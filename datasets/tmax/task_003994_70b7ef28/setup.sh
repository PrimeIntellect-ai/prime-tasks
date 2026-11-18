#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_fasta.py
import random
random.seed(42)

with open("/home/user/data.fasta", "w") as f:
    seq_specs = [(10, 30), (20, 50), (30, 20)]
    seq_id = 1

    for length, count in seq_specs:
        for _ in range(count):
            bases = ['G'] * (length - 1) + ['A']
            random.shuffle(bases)
            seq = "".join(bases)

            f.write(f">seq_{seq_id}\n")
            f.write(seq + "\n")
            seq_id += 1
EOF
    python3 /home/user/generate_fasta.py
    rm /home/user/generate_fasta.py

    chmod -R 777 /home/user
