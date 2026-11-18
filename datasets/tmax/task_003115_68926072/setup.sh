#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random

random.seed(42)

def generate_sequences(num_seqs, seq_len):
    bases = ['A', 'C', 'G', 'T']
    # Generate a common "genome" to sample from so there are actual overlaps
    genome_len = 1000
    genome = "".join(random.choices(bases, k=genome_len))

    seqs = []
    for _ in range(num_seqs):
        start = random.randint(0, genome_len - seq_len)
        seq = genome[start:start+seq_len]
        # Introduce a small mutation rate
        seq_mut = "".join([c if random.random() > 0.05 else random.choice(bases) for c in seq])
        seqs.append(seq_mut)
    return seqs

seqs = generate_sequences(250, 40)
with open("/home/user/sequences.fasta", "w") as f:
    for i, seq in enumerate(seqs):
        f.write(f">seq{i}\n{seq}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
