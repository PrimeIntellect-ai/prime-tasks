#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    # Create user home directory
    mkdir -p /home/user

    # Download json.hpp
    wget -O /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    # Generate raw_edges.json
    cat << 'EOF' > /home/user/generate_json.py
import json

edges = []
# Create a star graph around node 42 (degree 15)
for i in range(1, 16):
    edges.append({"src": 42, "dst": i, "interaction_type": "like"})
    edges.append({"src": i, "dst": 42, "interaction_type": "reply"}) # Duplicate undirected edge

# Create some other random edges
edges.append({"src": 100, "dst": 101, "interaction_type": "like"})
edges.append({"src": 101, "dst": 102, "interaction_type": "share"})
edges.append({"src": 100, "dst": 102, "interaction_type": "like"})

# Add another highly connected node, but lower degree than 42 (degree 10)
for i in range(200, 210):
    edges.append({"src": 999, "dst": i, "interaction_type": "like"})

with open('/home/user/raw_edges.json', 'w') as f:
    json.dump(edges, f)
EOF
    python3 /home/user/generate_json.py
    rm /home/user/generate_json.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
