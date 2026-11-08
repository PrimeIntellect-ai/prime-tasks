#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import random

os.makedirs('/home/user/data', exist_ok=True)

random.seed(42)
with open('/home/user/data/embeddings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'v1', 'v2', 'v3', 'v4', 'v5'])
    for i in range(100):
        vec = [round(random.uniform(0, 1), 4) for _ in range(5)]
        writer.writerow([f'doc_{i}'] + vec)

def calc_dist(vA, vB):
    return sum((a - b) ** 2 for a, b in zip(vA, vB))

with open('/home/user/data/embeddings.csv', 'r') as f:
    reader = csv.reader(f)
    next(reader)
    data = {row[0]: [float(x) for x in row[1:]] for row in reader}

target = data['doc_73']
dists = []
for k, v in data.items():
    if k == 'doc_73': continue
    dists.append((k, calc_dist(target, v)))

dists.sort(key=lambda x: x[1])
top_1 = dists[0][0]

with open('/home/user/data/baseline.txt', 'w') as f:
    f.write(f"{top_1}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
