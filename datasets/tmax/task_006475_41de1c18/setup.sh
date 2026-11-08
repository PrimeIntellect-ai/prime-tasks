#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/papers.jsonl
{"id": "P1", "title": "Deep Learning Foundations", "authors": ["Alice", "Bob"], "citations": [], "keywords": ["machine_learning", "neural_networks"]}
{"id": "P2", "title": "Optimization in NNs", "authors": ["Charlie"], "citations": ["P1"], "keywords": ["machine_learning", "math"]}
{"id": "P3", "title": "Advanced ML", "authors": ["Alice"], "citations": ["P1", "P2"], "keywords": ["machine_learning"]}
{"id": "P4", "title": "Database Systems", "authors": ["Dave"], "citations": ["P1"], "keywords": ["databases"]}
{"id": "P5", "title": "Graph Neural Networks", "authors": ["Eve"], "citations": ["P1", "P3"], "keywords": ["machine_learning", "graphs", "neural_networks"]}
EOF

    chmod -R 777 /home/user
