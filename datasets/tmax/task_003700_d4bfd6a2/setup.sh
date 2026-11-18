#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)

with open('/home/user/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'f1', 'y'])

    base_val = (1 << 60) + (1 << 50) + 123456789

    exact_sum = 0
    valid_count = 0

    rows = []
    for i in range(1000):
        if random.random() < 0.1:
            f1_val = "NaN"
            actual_f1 = 0
        else:
            f1_val = base_val + random.randint(-1000000, 1000000)
            exact_sum += f1_val
            valid_count += 1
            actual_f1 = f1_val

        if f1_val != "NaN":
            y = actual_f1 * 1.3e-10 + 0.1 + random.gauss(0, 0.05)
        else:
            y = 0.0

        rows.append({'id': i, 'f1': f1_val, 'y': y, 'is_nan': f1_val == "NaN"})

    imputed_mean = exact_sum // valid_count

    for r in rows:
        if r['is_nan']:
            r['y'] = imputed_mean * 1.3e-10 + 0.1 + random.gauss(0, 0.05)

        writer.writerow([r['id'], r['f1'], r['y']])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
