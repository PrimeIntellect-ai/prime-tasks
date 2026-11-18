#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest mongomock networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import json

data = [
    # Paper 1: Alice cites Bob (valid)
    {"paper_id": "p1", "author": "Alice", "cited_author": "Bob", "timestamp": 100, "is_deleted": False},
    # Paper 1: stale entry
    {"paper_id": "p1", "author": "Alice", "cited_author": "Bob", "timestamp": 50, "is_deleted": True},

    # Paper 2: Bob cites Charlie (deleted later)
    {"paper_id": "p2", "author": "Bob", "cited_author": "Charlie", "timestamp": 110, "is_deleted": False},
    {"paper_id": "p2", "author": "Bob", "cited_author": "Charlie", "timestamp": 120, "is_deleted": True},

    # Paper 3: Charlie cites Alice (valid)
    {"paper_id": "p3", "author": "Charlie", "cited_author": "Alice", "timestamp": 130, "is_deleted": False},
    {"paper_id": "p3", "author": "Charlie", "cited_author": "Dave", "timestamp": 90, "is_deleted": False}, # Stale

    # Paper 4: Alice cites Charlie (valid)
    {"paper_id": "p4", "author": "Alice", "cited_author": "Charlie", "timestamp": 140, "is_deleted": False},

    # Paper 5: Bob cites Alice (valid)
    {"paper_id": "p5", "author": "Bob", "cited_author": "Alice", "timestamp": 150, "is_deleted": False},
]

with open("/home/user/raw_citations.jsonl", "w") as f:
    for row in data:
        f.write(json.dumps(row) + "\n")
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
