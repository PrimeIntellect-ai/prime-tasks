#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph_db/nodes/
    cat << 'EOF' > /tmp/generate_graph.py
import json
import random
import os

random.seed(42)

NUM_NODES = 50
nodes = {}

for i in range(NUM_NODES):
    nodes[f"node_{i}"] = {
        "id": f"node_{i}",
        "weight": random.randint(5, 100),
        "linked_nodes": []
    }

# Create edges
for i in range(NUM_NODES):
    # Each node connects to 1-4 random forward nodes to create paths
    num_edges = random.randint(1, 4)
    for _ in range(num_edges):
        target = f"node_{random.randint(0, NUM_NODES-1)}"
        if target != f"node_{i}" and target not in nodes[f"node_{i}"]["linked_nodes"]:
            nodes[f"node_{i}"]["linked_nodes"].append(target)

# Ensure node_0 to node_49 has a specific known path
nodes["node_0"]["linked_nodes"].append("node_15")
nodes["node_15"]["linked_nodes"].append("node_30")
nodes["node_30"]["linked_nodes"].append("node_49")

# Make some nodes a closed loop disconnected from node_0
nodes["node_48"]["linked_nodes"] = ["node_47"]
nodes["node_47"]["linked_nodes"] = ["node_48"]

for node_id, data in nodes.items():
    with open(f"/home/user/graph_db/nodes/{node_id}.json", "w") as f:
        json.dump(data, f, indent=2)

EOF
    python3 /tmp/generate_graph.py
    rm /tmp/generate_graph.py

    chmod -R 777 /home/user
