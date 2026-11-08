#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /tmp/setup.py
import os
import random
import json
import math

random.seed(123)
os.makedirs('/home/user/data', exist_ok=True)

# Generate 500 sequences with a mean GC around 52% and std dev around 4%
sequences = []
gc_contents = []
for i in range(500):
    length = random.randint(100, 150)
    # Target GC for this sequence
    target_gc = random.gauss(0.52, 0.04)
    target_gc = max(0.0, min(1.0, target_gc))

    seq = []
    gc_count = 0
    for _ in range(length):
        if random.random() < target_gc:
            seq.append(random.choice(['G', 'C']))
            gc_count += 1
        else:
            seq.append(random.choice(['A', 'T']))
    sequences.append("".join(seq))
    gc_contents.append((gc_count / length) * 100)

with open('/home/user/data/reads.fasta', 'w') as f:
    for i, seq in enumerate(sequences):
        f.write(f">seq_{i}\n{seq}\n")

# Empirical mean and std
emp_mu = sum(gc_contents) / len(gc_contents)
emp_var = sum((x - emp_mu)**2 for x in gc_contents) / len(gc_contents)
emp_sigma = math.sqrt(emp_var)

legacy_data = {
    "kde_peak": 52.1,
    "mcmc_mu": emp_mu + 0.1,  # slightly offset to test tolerance
    "mcmc_sigma": emp_sigma - 0.1
}

with open('/home/user/data/legacy_results.json', 'w') as f:
    json.dump(legacy_data, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
