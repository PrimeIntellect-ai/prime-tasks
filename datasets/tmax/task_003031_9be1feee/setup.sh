#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_fasta.py
import random

random.seed(42)

def generate_fasta(filename, num_sequences):
    with open(filename, 'w') as f:
        for i in range(num_sequences):
            seq_len = random.randint(100, 1000)
            gc_prob = 0.4 + (seq_len / 5000.0) 

            sequence = []
            for _ in range(seq_len):
                if random.random() < gc_prob:
                    sequence.append(random.choice(['G', 'C']))
                else:
                    sequence.append(random.choice(['A', 'T']))

            seq_str = "".join(sequence)
            f.write(f">seq_{i}\n")
            for j in range(0, len(seq_str), 80):
                f.write(f"{seq_str[j:j+80]}\n")

generate_fasta('/home/user/sequences.fasta', 500)
EOF

    python3 /tmp/generate_fasta.py
    rm /tmp/generate_fasta.py

    chmod -R 777 /home/user
