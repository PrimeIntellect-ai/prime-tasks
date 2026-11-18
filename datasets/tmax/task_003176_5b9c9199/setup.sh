#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user/dataset/

    cat << 'EOF' > /home/user/dataset/nodes.jsonl
{"node_id": "p1", "title": "Graph DBs", "authors": ["Alice", "Bob"]}
{"node_id": "p2", "title": "NoSQL Joins", "authors": ["Bob", "Charlie"]}
{"node_id": "p3", "title": "AI Agents", "authors": ["David", "Eve"]}
{"node_id": "p4", "title": "Query Planning", "authors": ["Alice", "Frank"]}
{"node_id": "p5", "title": "Data Modeling", "authors": ["Charlie", "Eve", "Grace"]}
{"node_id": "p6", "title": "Bash Pipelines", "authors": ["Frank"]}
{"node_id": "p7", "title": "Graph Algorithms", "authors": ["Alice", "Grace"]}
EOF

    cat << 'EOF' > /home/user/dataset/edges.jsonl
{"src": "p2", "dst": "p1"}
{"src": "p3", "dst": "p1"}
{"src": "p4", "dst": "p1"}
{"src": "p5", "dst": "p2"}
{"src": "p5", "dst": "p3"}
{"src": "p6", "dst": "p4"}
{"src": "p7", "dst": "p1"}
{"src": "p7", "dst": "p5"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
