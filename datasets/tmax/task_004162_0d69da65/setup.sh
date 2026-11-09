#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
ref = np.random.uniform(0, 1, 100)
with open('/home/user/reference.csv', 'w') as f:
    f.write(','.join(map(str, ref)) + '\n')

valid_data = np.random.uniform(0, 1, (9500, 100))
corrupted_data = []

# Generate corrupted rows
for _ in range(200):
    corrupted_data.append(','.join(map(str, np.random.uniform(0, 1, 99)))) # Too short
for _ in range(150):
    corrupted_data.append(','.join(map(str, np.random.uniform(0, 1, 101)))) # Too long
for _ in range(150):
    bad_row = list(np.random.uniform(0, 1, 100))
    bad_row[50] = "corrupted_string" # Bad schema
    corrupted_data.append(','.join(map(str, bad_row)))

# Combine and shuffle
all_rows = [','.join(map(str, row)) for row in valid_data] + corrupted_data
np.random.shuffle(all_rows)

with open('/home/user/embeddings.csv', 'w') as f:
    for row in all_rows:
        f.write(row + '\n')

# Calculate ground truth
dots = np.dot(valid_data, ref)
mean = np.mean(dots)
std = np.std(dots, ddof=1)
n = 9500
ci_lower = mean - 1.96 * (std / np.sqrt(n))
ci_upper = mean + 1.96 * (std / np.sqrt(n))
status = "VALID" if mean > 25.0 else "INVALID"

with open('/home/user/.golden_results', 'w') as f:
    f.write(f"Valid Rows: {n}\n")
    f.write(f"Mean Dot Product: {mean:.4f}\n")
    f.write(f"95% CI Lower: {ci_lower:.4f}\n")
    f.write(f"95% CI Upper: {ci_upper:.4f}\n")
    f.write(f"Status: {status}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
