#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_network.py
import csv
import random
import networkx as nx

random.seed(42)
G = nx.barabasi_albert_graph(100, 3, seed=42)
edges = []
for u, v in G.edges():
    weight = round(random.uniform(0.1, 10.0), 2)
    edges.append((u, v, weight))
    # Add some directedness
    if random.random() > 0.5:
        edges.append((v, u, round(random.uniform(0.1, 10.0), 2)))

with open('/home/user/network.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target', 'weight'])
    writer.writerows(edges)
EOF

    python3 /tmp/generate_network.py
    rm /tmp/generate_network.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
