#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest matplotlib pandas

    useradd -m -s /bin/bash user || true

    # Generate data
    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)
random.seed(42)

target_seq = "ATGCGTACGTAGCTA"
K = 10000
counts = [100, 149, 222, 330, 485, 706, 1014, 1432, 1980, 2680]

def generate_random_dna(length):
    return ''.join(random.choices('ACGT', k=length))

def mutate_string(s, num_mutations):
    s_list = list(s)
    indices = random.sample(range(len(s)), num_mutations)
    for idx in indices:
        current = s_list[idx]
        choices = [c for c in 'ACGT' if c != current]
        s_list[idx] = random.choice(choices)
    return ''.join(s_list)

for day, count in enumerate(counts, 1):
    filename = f'/home/user/data/day_{day}.fasta'
    with open(filename, 'w') as f:
        for i in range(count):
            mismatches = random.choice([0, 1])
            implanted = mutate_string(target_seq, mismatches)
            prefix = generate_random_dna(random.randint(0, 30))
            suffix = generate_random_dna(random.randint(0, 30))
            seq = prefix + implanted + suffix
            f.write(f">seq_{i}_match\n{seq}\n")

        noise_count = 500 - count 
        for i in range(noise_count):
            seq = generate_random_dna(50)
            f.write(f">seq_{i}_noise\n{seq}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
