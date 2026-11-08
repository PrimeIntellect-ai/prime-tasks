#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the initial dataset
    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)
random.seed(42)

for i in range(100):
    num_nodes = random.randint(10, 50)
    num_edges = random.randint(num_nodes, num_nodes * 3)

    edges = set()
    for _ in range(num_edges):
        u = random.randint(0, num_nodes - 1)
        v = random.randint(0, num_nodes - 1)
        if u != v:
            edges.add(tuple(sorted((u, v))))

    with open(f'/home/user/data/graph_{i}.txt', 'w') as f:
        for u, v in edges:
            f.write(f"{u},{v}\n")
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
