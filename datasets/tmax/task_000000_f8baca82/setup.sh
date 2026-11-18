#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import json
import networkx as nx

# Create CSV
csv_path = '/home/user/network_data.csv'
data = [
    {"tx_id": 1, "sender": "Alice", "receiver": "Bob", "amount": 10.0, "timestamp": 1},
    {"tx_id": 2, "sender": "Alice", "receiver": "Charlie", "amount": 20.0, "timestamp": 2},
    {"tx_id": 3, "sender": "Alice", "receiver": "Bob", "amount": 30.0, "timestamp": 3},
    {"tx_id": 4, "sender": "Bob", "receiver": "Charlie", "amount": 15.0, "timestamp": 4},
    {"tx_id": 5, "sender": "Charlie", "receiver": "Alice", "amount": 5.0, "timestamp": 5},
    {"tx_id": 6, "sender": "Alice", "receiver": "Charlie", "amount": 40.0, "timestamp": 6},
    {"tx_id": 7, "sender": "David", "receiver": "Bob", "amount": 100.0, "timestamp": 7},
]

os.makedirs('/home/user', exist_ok=True)
with open(csv_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["tx_id", "sender", "receiver", "amount", "timestamp"])
    writer.writeheader()
    for row in data:
        writer.writerow(row)

# Ground Truth Calculation
rolling_avg = {
    "Alice": 30.0,
    "Bob": 15.0,
    "Charlie": 5.0,
    "David": 100.0
}

G = nx.DiGraph()
G.add_edge("Alice", "Bob", weight=40.0)
G.add_edge("Alice", "Charlie", weight=60.0)
G.add_edge("Bob", "Charlie", weight=15.0)
G.add_edge("Charlie", "Alice", weight=5.0)
G.add_edge("David", "Bob", weight=100.0)

pr = nx.pagerank(G, alpha=0.85, weight='weight')

# Output formatting
output = []
for node in sorted(list(G.nodes())):
    output.append({
        "node": node,
        "max_rolling_3_avg": round(rolling_avg.get(node, 0.0), 4),
        "pagerank": round(pr[node], 4)
    })

with open('/home/user/.truth.json', 'w') as f:
    json.dump(output, f, indent=2)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
