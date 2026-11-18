#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np

# Create a deterministic sequence
# Length 11 pattern: 'ATGCGCATGCA'
pattern = "ATGCGCATGCA"
repeats = 10000
seq = pattern * repeats # 110,000 length

with open('/home/user/sequence.fasta', 'w') as f:
    f.write(">sequence_1 hidden_periodicity=11\n")
    # write in chunks of 80
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + "\n")
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
