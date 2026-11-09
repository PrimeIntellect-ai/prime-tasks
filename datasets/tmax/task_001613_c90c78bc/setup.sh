#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/nodes.jsonl
{"id": "N1", "type": "Author", "field": "AI", "extra": "data"}
{"id": "N2", "type": "Author", "field": "AI"}
{"id": "N3", "type": "Author", "field": "AI"}
{"id": "N4", "type": "Author", "field": "AI"}
{"id": "N5", "type": "Author", "field": "BIO"}
{"id": "N6", "type": "Author", "field": "BIO"}
{"id": "N7", "type": "Author", "field": "BIO"}
{"id": "N8", "type": "Paper", "field": "AI"}
EOF

    cat << 'EOF' > /home/user/dataset/edges.jsonl
{"src": "N1", "dst": "N2", "rel": "CITES"}
{"src": "N2", "dst": "N3", "rel": "CITES"}
{"src": "N1", "dst": "N3", "rel": "CITES"}
{"src": "N2", "dst": "N4", "rel": "CITES"}
{"src": "N3", "dst": "N1", "rel": "CITES"}
{"src": "N1", "dst": "N4", "rel": "CITES"}
{"src": "N5", "dst": "N6", "rel": "CITES"}
{"src": "N6", "dst": "N7", "rel": "CITES"}
{"src": "N5", "dst": "N1", "rel": "CITES"}
{"src": "N8", "dst": "N1", "rel": "MENTIONS"}
EOF

    chmod -R 777 /home/user
