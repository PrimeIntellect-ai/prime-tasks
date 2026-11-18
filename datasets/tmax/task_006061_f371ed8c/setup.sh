#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/knowledge_graph.json
{
  "nodes": [
    {"id": "A1", "type": "author", "name": "Dr. Alice"},
    {"id": "A2", "type": "author", "name": "Dr. Bob"},
    {"id": "A3", "type": "author", "name": "Dr. Charlie"},
    {"id": "A4", "type": "author", "name": "Dr. Diana"},
    {"id": "P1", "type": "paper"},
    {"id": "P2", "type": "paper"},
    {"id": "P3", "type": "paper"},
    {"id": "P4", "type": "paper"},
    {"id": "C1", "type": "concept", "name": "Machine Learning"},
    {"id": "C2", "type": "concept", "name": "Bioinformatics"}
  ],
  "edges": [
    {"source": "A1", "target": "P1", "relation": "authored"},
    {"source": "P1", "target": "C1", "relation": "covers"},
    {"source": "A2", "target": "P2", "relation": "authored"},
    {"source": "P2", "target": "C1", "relation": "covers"},
    {"source": "A3", "target": "P3", "relation": "authored"},
    {"source": "P3", "target": "C2", "relation": "covers"},
    {"source": "A4", "target": "P4", "relation": "authored"},
    {"source": "P4", "target": "C1", "relation": "covers"},
    {"source": "A1", "target": "P3", "relation": "authored"}
  ]
}
EOF

    chmod -R 777 /home/user
