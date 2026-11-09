#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import networkx as nx
import csv
import random
import os

random.seed(42)

G = nx.barabasi_albert_graph(500, 3, seed=42)
G = G.to_directed()

nodes_data = []
core_nodes = set()
for n in G.nodes():
    category = 'CORE' if n < 300 else 'AUX'
    if category == 'CORE':
        core_nodes.add(n)
    name = f"Entity_Name_{n}_{category}"
    nodes_data.append([category, n, name])

edges_data = []
for u, v in G.edges():
    timestamp = random.randint(1600000000, 1700000000)
    edges_data.append([timestamp, u, v])

with open('/home/user/entities.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(nodes_data)

with open('/home/user/connections.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(edges_data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
