#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_embeddings.jsonl
{"id": "doc1", "vector": [1.0, 0.0, 2.0, -1.0]}
{"id": "doc2", "vector": [0.5, 0.5, 0.5, 0.5]}
{"id": "doc3", "vector": [10.0, 0.0, 0.0, 0.0]}
{"id": "doc4", "vector": [-1.0, -1.0, -1.0, -1.0]}
{"id": "doc5", "vector": [0.0, 0.0, 0.0, 0.0]}
EOF

    cat << 'EOF' > /home/user/data/projection_matrix.csv
0.5,-0.5
0.5,0.5
-0.5,0.5
-0.5,-0.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
