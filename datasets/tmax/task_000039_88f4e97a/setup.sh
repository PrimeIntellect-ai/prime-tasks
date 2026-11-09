#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup.py
import csv
import random

random.seed(42)

# Generate Nodes
node_types = ["Distribution Center", "Warehouse", "Retail Store"]
nodes = []
for i in range(1, 101):
    ntype = random.choice(node_types)
    if i % 3 == 0:
        ntype = "Distribution Center"
    nodes.append({"node_id": f"N{i:03d}", "node_type": ntype})

with open("/home/user/data/nodes.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["node_id", "node_type"])
    writer.writeheader()
    writer.writerows(nodes)

# Generate Edges
edges = []
for _ in range(300):
    src = f"N{random.randint(1, 100):03d}"
    dst = f"N{random.randint(1, 100):03d}"
    if src != dst:
        edges.append({"src": src, "dst": dst, "cost": round(random.uniform(10.0, 100.0), 2)})

with open("/home/user/data/edges.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["src", "dst", "cost"])
    writer.writeheader()
    writer.writerows(edges)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "node_id": { "type": "string" },
      "node_type": { "type": "string" },
      "pagerank": { "type": "number" },
      "community_id": { "type": "integer" }
    },
    "required": ["node_id", "node_type", "pagerank", "community_id"],
    "additionalProperties": false
  }
}
EOF

    chmod -R 777 /home/user
