#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.jsonl
{"id": "N1", "field": "neuroscience", "cited_by": ["A","B"]}
{"id": "C1", "field": "cs", "cited_by": ["A"]}
{"id": "N2", "field": "neuroscience", "cited_by": ["A","B","C","D"]}
{"id": "N3", "field": "neuroscience", "cited_by": ["A"]}
{"id": "N4", "field": "neuroscience", "cited_by": ["B","C","D"]}
{"id": "N5", "field": "neuroscience", "cited_by": ["A","B","C","D","E"]}
{"id": "N6", "field": "neuroscience", "cited_by": ["A","B"]}
{"id": "N7", "field": "neuroscience", "cited_by": []}
{"id": "N8", "field": "neuroscience", "cited_by": ["A","B","C"]}
EOF

    chmod 644 /home/user/dataset.jsonl
    chmod -R 777 /home/user
