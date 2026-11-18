#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create dataset.json
    cat << 'EOF' > /home/user/dataset.json
{
  "nodes": [
    {"id": "A1", "type": "Author"},
    {"id": "A2", "type": "Author"},
    {"id": "A3", "type": "Author"},
    {"id": "A4", "type": "Author"},
    {"id": "A5", "type": "Author"},
    {"id": "P1", "type": "Paper"},
    {"id": "P2", "type": "Paper"},
    {"id": "P3", "type": "Paper"},
    {"id": "P4", "type": "Paper"}
  ],
  "edges": [
    {"source": "A1", "target": "P1"},
    {"source": "A2", "target": "P1"},
    {"source": "A3", "target": "P1"},
    {"source": "A2", "target": "P2"},
    {"source": "A3", "target": "P2"},
    {"source": "A4", "target": "P2"},
    {"source": "A5", "target": "P2"},
    {"source": "A1", "target": "P3"},
    {"source": "A3", "target": "P3"},
    {"source": "A5", "target": "P3"},
    {"source": "A1", "target": "P4"},
    {"source": "A4", "target": "P4"},
    {"source": "A5", "target": "P4"}
  ]
}
EOF

    chmod -R 777 /home/user
