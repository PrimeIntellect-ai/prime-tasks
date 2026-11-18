#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/genomics_data

    cat << 'EOF' > /home/user/generate_fasta.py
import random

random.seed(42)
bases = ['A', 'C', 'G', 'T']
primer = "CGTAGCTAGCC"

with open("/home/user/genomics_data/sequences.fasta", "w") as f:
    for i in range(1, 101):
        seq_len = random.randint(50, 150)
        # occasionally inject a near-match of the primer to create variance
        seq = "".join(random.choices(bases, k=seq_len))
        if random.random() > 0.7:
            insert_pos = random.randint(0, len(seq) - len(primer))
            mutated_primer = "".join([b if random.random() > 0.1 else random.choice(bases) for b in primer])
            seq = seq[:insert_pos] + mutated_primer + seq[insert_pos + len(primer):]

        f.write(f">seq_{i}\n")
        f.write(f"{seq}\n")
EOF
    python3 /home/user/generate_fasta.py
    rm /home/user/generate_fasta.py

    chmod -R 777 /home/user
