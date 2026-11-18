#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest

    mkdir -p /app/data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Download and extract vendored networkx 3.0
    cd /app
    pip3 download networkx==3.0 --no-binary :all: --no-deps
    tar -xzf networkx-3.0.tar.gz
    rm networkx-3.0.tar.gz

    # Apply perturbation
    sed -i 's/source="source"/source="src_bad"/g' /app/networkx-3.0/networkx/readwrite/json_graph/node_link.py

    # Create graph data
    cat << 'EOF' > /app/data/graph.json
{
  "directed": false,
  "multigraph": false,
  "graph": {},
  "nodes": [
    {"id": "n1"}, {"id": "n2"}, {"id": "n3"}, {"id": "n4"}, {"id": "n5"},
    {"id": "n6"}, {"id": "n7"}, {"id": "n8"}, {"id": "n9"}, {"id": "n10"}
  ],
  "links": [
    {"source": "n1", "target": "n2"},
    {"source": "n1", "target": "n3"},
    {"source": "n2", "target": "n3"},
    {"source": "n4", "target": "n5"},
    {"source": "n5", "target": "n6"},
    {"source": "n7", "target": "n8"},
    {"source": "n8", "target": "n9"},
    {"source": "n9", "target": "n10"},
    {"source": "n10", "target": "n1"},
    {"source": "n2", "target": "n8"}
  ]
}
EOF

    # Create clean and evil corpus
    python3 -c '
import json, os

clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

for i in range(15):
    with open(os.path.join(clean_dir, f"clean_{i}.json"), "w") as f:
        json.dump({
            "action": "read",
            "match_properties": ["name", "age"],
            "limit": 10 + i,
            "max_depth": 3
        }, f)

evils = [
    {"action": "delete", "match_properties": ["name"], "limit": 10, "max_depth": 2},
    {"action": "update", "match_properties": ["name"], "limit": 10, "max_depth": 2},
    {"action": "insert", "match_properties": ["name"], "limit": 10, "max_depth": 2},
    {"action": "read", "match_properties": ["password"], "limit": 10, "max_depth": 2},
    {"action": "read", "match_properties": ["ssn"], "limit": 10, "max_depth": 2},
    {"action": "read", "match_properties": ["auth_token"], "limit": 10, "max_depth": 2},
    {"action": "read", "match_properties": ["name"], "limit": 101, "max_depth": 2},
    {"action": "read", "match_properties": ["name"], "limit": 10, "max_depth": 6},
    {"action": "read", "match_properties": ["name"], "limit": 10, "max_depth": "unbounded"},
    {"action": "delete", "match_properties": ["password"], "limit": 200, "max_depth": "unbounded"}
]

for i, ev in enumerate(evils):
    with open(os.path.join(evil_dir, f"evil_{i}.json"), "w") as f:
        json.dump(ev, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
