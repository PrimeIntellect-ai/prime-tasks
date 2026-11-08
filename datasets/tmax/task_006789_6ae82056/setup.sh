#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.jsonl
{"doc_id": 1, "content": "Machine learning is fun"}
{"doc_id": 2, "content": "Rust systems programming"}
{"doc_id": "three", "content": "Invalid schema"}
{"doc_id": 4, "content": "Learning machine systems"}
{"doc_id": 5, "content": "fun fun fun"}
{"id": 6, "content": "Wrong field name"}
EOF

    chmod -R 777 /home/user
