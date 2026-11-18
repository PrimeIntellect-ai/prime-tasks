#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/papers.jsonl
{"paper_id": "p1", "year": 2021, "authors": ["Alice", "Bob", "Charlie"], "references": []}
{"paper_id": "p2", "year": 2019, "authors": ["Bob", "Dave"], "references": ["p1"]}
{"paper_id": "p3", "year": 2022, "authors": ["Alice", "Dave"], "references": ["p1"]}
{"paper_id": "p4", "year": 2021, "authors": ["Charlie", "Eve"], "references": []}
{"paper_id": "p5", "year": 2020, "authors": ["Alice", "Bob"], "references": []}
{"paper_id": "p6", "year": 2023, "authors": ["Dave", "Frank"], "references": ["p4", "p2"]}
{"paper_id": "p7", "year": 2021, "authors": ["Alice", "Charlie"], "references": []}
EOF

    chmod 644 /home/user/papers.jsonl
    chmod -R 777 /home/user
