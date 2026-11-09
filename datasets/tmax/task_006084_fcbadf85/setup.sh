#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import math

# Create sequence file
csv_path = "/home/user/sequences.csv"
sequences = [
    ("SEQ1", "WT", "ATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGC"),
    ("SEQ2", "WT", "GGGGGGGGGGGGGGGGGGGGAAAAAAAAAAAAAAAAAAAAGGGGGGGGGGGGGGGGGGGGAAAAAAAAAAAAAAAAAAAAGGGGGGGGGGGGGGGGGGGG"),
    ("SEQ3", "MUT", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
    ("SEQ4", "MUT", "ATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATAT")
]

with open(csv_path, "w") as f:
    for seq_id, seq_type, seq in sequences:
        f.write(f"{seq_id},{seq_type},{seq}\n")

# Calculate Truth
def gc_prop(seq, i):
    window = seq[i:i+10]
    return (window.count('G') + window.count('C')) / 10.0

integrals = {'WT': [], 'MUT': []}
seq1_max_diff = -1
seq1_max_idx = -1

for seq_id, seq_type, seq in sequences:
    p = [gc_prop(seq, i) for i in range(91)]

    # Differentiation for SEQ1
    if seq_id == "SEQ1":
        for i in range(90):
            diff = p[i+1] - p[i]
            if diff > seq1_max_diff:
                seq1_max_diff = diff
                seq1_max_idx = i

    # Integration
    s = sum((p[i] + p[i+1])/2.0 for i in range(90))
    integrals[seq_type].append(s)

def get_stats(vals):
    n = len(vals)
    mean = sum(vals)/n
    var = sum((x - mean)**2 for x in vals)/(n-1) if n > 1 else 0
    return n, mean, var

n_wt, mu_wt, var_wt = get_stats(integrals['WT'])
n_mut, mu_mut, var_mut = get_stats(integrals['MUT'])

z_stat = (mu_wt - mu_mut) / math.sqrt(var_wt/n_wt + var_mut/n_mut)

expected_output = f"""WT_MEAN_INTEGRAL: {mu_wt:.4f}
MUT_MEAN_INTEGRAL: {mu_mut:.4f}
Z_STATISTIC: {z_stat:.4f}
SEQ1_MAX_DERIVATIVE_INDEX: {seq1_max_idx}
"""

with open("/home/user/.expected_output", "w") as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
