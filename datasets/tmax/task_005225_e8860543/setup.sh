#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import random
import csv
import math

random.seed(42)

def generate_vector(dim=5):
    return [round(random.uniform(-1, 1), 4) for _ in range(dim)]

# Generate query
query = generate_vector()
with open('/home/user/data/query.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(query)

# Generate dataset
with open('/home/user/data/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for i in range(1, 501):
        doc_id = f"doc_{i:03d}"
        vec = generate_vector()
        writer.writerow([doc_id] + vec)
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
