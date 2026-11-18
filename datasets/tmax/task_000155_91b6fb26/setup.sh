#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/config.ini
[Settings]
chunk_size = 1
EOF

    cat << 'EOF' > /home/user/pipeline/aggregator.py
import configparser
import csv
import math

def process_data(filepath):
    config = configparser.ConfigParser()
    config.read('/home/user/pipeline/config.ini')
    chunk_size = int(config['Settings']['chunk_size'])

    naive_sum = 0.0
    # TODO: Calculate precise_sum and track corrupted_count

    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            val = row[0]
            # This will crash on corrupted input
            f_val = float(val)
            naive_sum += f_val

    return naive_sum
EOF

    python3 -c "
with open('/home/user/pipeline/data.csv', 'w') as f:
    # 10,000 small floats
    for _ in range(10000):
        f.write('0.1\n')
    # 50 corrupted lines
    for _ in range(50):
        f.write('ERROR_CORRUPT\n')
    # 1 massive float
    f.write('1e16\n')
    # 10,000 small floats (will be lost in naive summation)
    for _ in range(10000):
        f.write('0.1\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
