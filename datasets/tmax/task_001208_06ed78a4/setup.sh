#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import gzip
import csv
import random

os.makedirs('/home/user/artifacts', exist_ok=True)
random.seed(42)

N = 10000
num_files = 10
records_per_file = N // num_files

record_id = 0
for i in range(num_files):
    filepath = f'/home/user/artifacts/part-{i:04d}.csv.gz'
    with gzip.open(filepath, 'wt', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'y_true', 'y_pred_A', 'y_pred_B'])
        for _ in range(records_per_file):
            y_true = random.uniform(0, 100)
            err_a = random.gauss(0, 5.0)
            err_b = random.gauss(0, 4.8)

            y_pred_a = y_true + err_a
            y_pred_b = y_true + err_b

            writer.writerow([record_id, round(y_true,4), round(y_pred_a,4), round(y_pred_b,4)])
            record_id += 1
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
