#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the dataset
    mkdir -p /home/user
    cat << 'EOF' > /home/user/social_graph.jsonl
{"src": "A", "dst": "B", "rel": "mentions"}
{"src": "C", "dst": "B", "rel": "mentions"}
{"src": "B", "dst": "D", "rel": "mentions"}
{"src": "E", "dst": "F", "rel": "mentions"}
{"src": "A", "dst": "F", "rel": "mentions"}
{"src": "G", "dst": "H", "rel": "mentions"}
{"src": "I", "dst": "J", "rel": "mentions"}
{"src": "X", "dst": "B", "rel": "follows"}
{"src": "Y", "dst": "B", "rel": "follows"}
{"src": "Z", "dst": "F", "rel": "follows"}
{"src": "W", "dst": "F", "rel": "follows"}
{"src": "V", "dst": "F", "rel": "follows"}
{"src": "U", "dst": "H", "rel": "follows"}
{"src": "T", "dst": "H", "rel": "follows"}
{"src": "S", "dst": "H", "rel": "follows"}
{"src": "R", "dst": "H", "rel": "follows"}
{"src": "Q", "dst": "J", "rel": "follows"}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
