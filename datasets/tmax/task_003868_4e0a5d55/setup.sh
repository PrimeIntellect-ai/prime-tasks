#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import math

random.seed(42)

rows = []
valid_vals = []

# Generate 100 rows
for i in range(1, 101):
    is_missing = random.random() < 0.1
    is_outlier = random.random() < 0.05

    if is_missing:
        val = ""
    elif is_outlier:
        val = round(random.uniform(500, 1000), 2) # High outlier
        valid_vals.append(val)
    else:
        val = round(random.normalvariate(50, 5), 2)
        valid_vals.append(val)

    num_words = random.randint(0, 5)
    if num_words == 0:
        text = ""
    else:
        text = " ".join(["word" + str(random.randint(1, 100)) for _ in range(num_words)])

    rows.append([i, val, text])

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'sensor_val', 'text_note'])
    writer.writerows(rows)

# Calculate ground truth
mean = sum(valid_vals) / len(valid_vals)

imputed_vals = []
for r in rows:
    if r[1] == "":
        imputed_vals.append(mean)
    else:
        imputed_vals.append(r[1])

variance = sum((x - mean) ** 2 for x in imputed_vals) / len(imputed_vals)
std_dev = math.sqrt(variance)

surviving_rows = 0
out_rows = []
for r, imp_val in zip(rows, imputed_vals):
    if abs(imp_val - mean) <= 2.0 * std_dev:
        surviving_rows += 1
        tokens = len(r[2].split()) if r[2] else 0
        fold = r[0] % 3
        out_rows.append(f"{r[0]},{imp_val:.4f},{tokens},{fold}")

with open('/home/user/ground_truth_log.txt', 'w') as f:
    f.write(f"Original Rows: 100\n")
    f.write(f"Mean: {mean:.4f}\n")
    f.write(f"StdDev: {std_dev:.4f}\n")
    f.write(f"Surviving Rows: {surviving_rows}\n")

with open('/home/user/ground_truth_csv.csv', 'w') as f:
    f.write("id,imputed_sensor_val,token_count,fold\n")
    for r in out_rows:
        f.write(r + "\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
