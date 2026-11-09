#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libfftw3-dev liblapacke-dev
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/generate_seqs.py
import random
random.seed(42)

def generate_seq(pattern, length):
    return (pattern * (length // len(pattern))) + pattern[:length % len(pattern)]

seq1 = generate_seq("ACTG", 1024)
seq2 = generate_seq("AAAA", 1024)
seq3 = generate_seq("CGCG", 1024)
seq4 = "".join(random.choices(["A", "C", "G", "T"], k=1024))

with open("/home/user/data/seqs.txt", "w") as f:
    f.write(seq1 + "\n")
    f.write(seq2 + "\n")
    f.write(seq3 + "\n")
    f.write(seq4 + "\n")
EOF

    python3 /home/user/data/generate_seqs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
