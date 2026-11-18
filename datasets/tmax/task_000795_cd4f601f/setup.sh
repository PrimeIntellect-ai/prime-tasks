#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user/dataset
    cat << 'EOF' > /home/user/dataset/setup.py
import csv
import random

edges = set()
# Create some random noise
for _ in range(500):
    u = random.randint(1, 150)
    v = random.randint(1, 150)
    if u != v:
        edges.add((u, v))

# Ensure the shortest path exists: 10 -> 25 -> 40 -> 88 -> 99
path_edges = [(10, 25), (25, 40), (40, 88), (88, 99)]
for edge in path_edges:
    edges.add(edge)

# Remove any shortcut edges that might bypass our intended path
shortcuts = [(10, 40), (10, 88), (10, 99), (25, 88), (25, 99), (40, 99)]
for edge in shortcuts:
    if edge in edges:
        edges.remove(edge)

with open('/home/user/dataset/citations.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target'])
    for u, v in edges:
        writer.writerow([u, v])
EOF
    python3 /home/user/dataset/setup.py
    rm /home/user/dataset/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
