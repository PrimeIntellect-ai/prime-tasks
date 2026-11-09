#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep bash coreutils
    pip3 install pytest

    # Generate the initial FASTA file
    cat << 'EOF' > /tmp/setup.py
import random
import os

random.seed(42)
seq_list = random.choices(['A','C','G','T'], k=10000)
seq = ''.join(seq_list)

# Inject sharp GC gradient to ensure a unique max
gc_block = ''.join(random.choices(['G','C'], k=100))
at_block = ''.join(random.choices(['A','T'], k=100))
seq = seq[:4000] + gc_block + at_block + seq[4200:]

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/dna_sequence.fasta', 'w') as f:
    f.write(">chr1_synthetic\n")
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + "\n")
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
