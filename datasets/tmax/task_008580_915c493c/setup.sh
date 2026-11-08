#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_fasta.py
import os
import random

random.seed(123)
fasta_path = "/home/user/raw_sequences.fasta"

with open(fasta_path, "w") as f:
    for i in range(1000):
        f.write(f">seq_{i}\n")

        has_motif = random.random() < 0.6

        if has_motif:
            prefix = "".join(random.choices("ACGT", k=random.randint(5, 20)))
            target_len = random.randint(10, 50)
            target = "".join(random.choices("ACGT", weights=[0.2, 0.3, 0.3, 0.2], k=target_len))
            suffix = "".join(random.choices("ACGT", k=random.randint(5, 20)))

            seq = prefix + "GACCAT" + target + "TGTCGA" + suffix
        else:
            seq = "".join(random.choices("ACGT", k=random.randint(30, 100)))

        f.write(f"{seq}\n")
EOF

    python3 /tmp/generate_fasta.py
    rm /tmp/generate_fasta.py

    chmod -R 777 /home/user
