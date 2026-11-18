#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Generate the initial data
    cat << 'EOF' > /tmp/generate_data.py
import os
import math
import csv

os.makedirs('/home/user', exist_ok=True)
data_path = '/home/user/raw_spectra.csv'

matrix = []
for i in range(10):
    row = []
    for j in range(100):
        val = (i + 1) * math.sin(j / 10.0) + 50.0
        row.append(val)
    matrix.append(row)

with open(data_path, 'w', newline='') as f:
    writer = csv.writer(f)
    for row in matrix:
        writer.writerow(row)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
