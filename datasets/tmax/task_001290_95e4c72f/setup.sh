#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/setup_data.py
import csv
import random
import numpy as np
import json

random.seed(42)
np.random.seed(42)

num_valid = 500
num_corrupted = 50

fasta_file = "/home/user/data/sequences.fasta"
csv_file = "/home/user/data/growth_rates.csv"

# True params
true_b0 = 0.5
true_b1 = 2.0

seqs = {}
growth_rates = {}

# Generate valid sequences
for i in range(num_valid):
    seq_id = f"seq_{i}"
    length = random.randint(100, 500)
    gc_target = random.uniform(0.3, 0.7)

    seq = []
    for _ in range(length):
        if random.random() < gc_target:
            seq.append(random.choice(['G', 'C']))
        else:
            seq.append(random.choice(['A', 'T']))
    seq_str = "".join(seq)
    seqs[seq_id] = seq_str

    # Calculate exact GC to generate Y
    gc_actual = (seq_str.count('G') + seq_str.count('C')) / len(seq_str)
    y = true_b0 + true_b1 * gc_actual + np.random.normal(0, 0.1)
    growth_rates[seq_id] = y

# Generate corrupted sequences
for i in range(num_corrupted):
    seq_id = f"bad_{i}"
    # Corrupted: only Ns
    seq_str = "N" * random.randint(50, 200)
    seqs[seq_id] = seq_str
    # They might have a CSV entry, but should be filtered out!
    growth_rates[seq_id] = 999.9  # Would heavily skew if included

# Write FASTA
with open(fasta_file, "w") as f:
    for sid, s in seqs.items():
        f.write(f">{sid}\n")
        # split into lines of 80
        for j in range(0, len(s), 80):
            f.write(s[j:j+80] + "\n")

# Write CSV
with open(csv_file, "w", newline="") as f:
    writer = csv.writer(f)
    for sid, y in growth_rates.items():
        writer.writerow([sid, round(y, 4)])

# Calculate Golden OLS values
x_vals = []
y_vals = []
for sid in seqs:
    if sid.startswith("seq_"):
        s = seqs[sid]
        gc = (s.count('G') + s.count('C')) / len(s)
        x_vals.append(gc)
        y_vals.append(growth_rates[sid])

x_mean = np.mean(x_vals)
y_mean = np.mean(y_vals)

cov = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_vals, y_vals))
var = sum((x - x_mean)**2 for x in x_vals)

b1 = cov / var
b0 = y_mean - b1 * x_mean

with open("/home/user/data/golden.json", "w") as f:
    json.dump({"beta_0": round(b0, 4), "beta_1": round(b1, 4)}, f)

EOF

    python3 /home/user/data/setup_data.py
    chmod -R 777 /home/user
