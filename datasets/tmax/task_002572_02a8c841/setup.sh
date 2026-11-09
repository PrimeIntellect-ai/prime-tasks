#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /app/vendored/py-graph-engine/core

    # Generate dataset
    cat << 'EOF' > /tmp/generate_data.py
import json
import random

random.seed(42)
authors = [f"Author_{i}" for i in range(200)]
with open('/home/user/data/papers.jsonl', 'w') as f:
    for i in range(2000):
        year = random.randint(2000, 2022)
        num_authors = random.randint(1, 5)
        paper_authors = random.sample(authors, num_authors)
        paper = {
            "paper_id": f"P{i}",
            "year": year,
            "authors": paper_authors,
            "citations": []
        }
        f.write(json.dumps(paper) + '\n')
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Create vendored package files
    touch /app/vendored/py-graph-engine/__init__.py
    touch /app/vendored/py-graph-engine/core/__init__.py

    cat << 'EOF' > /app/vendored/py-graph-engine/core/executor.py
def build_edge_list(sources, targets):
    edges = []
    # DELIBERATE BUG: O(N^2) Nested loop join mimicking bad query execution plan
    for s in sources:
        for t in targets:
            if s['ref_id'] == t['node_id']:
                edges.append((s['node_id'], t['node_id'], s['weight']))
    return edges
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
