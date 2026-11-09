#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    # Create data directory
    mkdir -p /home/user/data

    # Generate data
    cat << 'EOF' > /tmp/setup_data.py
import os
import random
import math

os.makedirs('/home/user/data', exist_ok=True)

random.seed(42)

def generate_vector():
    return " ".join([str(round(random.uniform(-1.0, 1.0), 4)) for _ in range(50)])

with open('/home/user/data/queries.csv', 'w') as f:
    f.write("query_id,vector\n")
    for i in range(1, 51):
        f.write(f"A{i:03d},{generate_vector()}\n")
    for i in range(1, 51):
        # Shift B vectors slightly so hypothesis test has an effect
        vec = " ".join([str(round(random.uniform(-0.8, 1.2), 4)) for _ in range(50)])
        f.write(f"B{i:03d},{vec}\n")

with open('/home/user/data/corpus.csv', 'w') as f:
    f.write("item_id,vector\n")
    for i in range(1, 201):
        f.write(f"ITEM{i:03d},{generate_vector()}\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
