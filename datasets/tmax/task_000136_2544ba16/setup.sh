#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk gnuplot
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_fasta.py
import random
random.seed(123)
with open("/home/user/sequences.fasta", "w") as f:
    for i in range(50):
        seq = "".join(random.choices("ACGT", k=100))
        f.write(f">seq_{i+1}\n{seq}\n")
EOF
    python3 /home/user/generate_fasta.py
    rm /home/user/generate_fasta.py

    chmod -R 777 /home/user
