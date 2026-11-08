#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)

random.seed(42)
bases = ['A', 'C', 'G', 'T']
seq_len = 40
num_seqs = 30

fasta_path = '/home/user/data/seqs.fasta'
labels_path = '/home/user/data/labels.csv'

with open(fasta_path, 'w') as f_fasta, open(labels_path, 'w') as f_labels:
    f_labels.write("seq_id,label\n")
    for i in range(num_seqs):
        seq_id = f"seq_{i:02d}"
        seq = "".join(random.choices(bases, k=seq_len))
        # Force the primer in some sequences
        if random.random() > 0.4:
            insert_pos = random.randint(0, seq_len - 5)
            seq = seq[:insert_pos] + "GATCA" + seq[insert_pos+5:]

        f_fasta.write(f">{seq_id}\n{seq}\n")
        label = 1 if (seq.count('A') > 10) else 0
        f_labels.write(f"{seq_id},{label}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
