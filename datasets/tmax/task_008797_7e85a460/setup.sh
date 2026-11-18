#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest networkx jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metadata.jsonl
{"paper_id": "p1", "citation_count": 50, "datasets": ["d1", "d2"], "citations": []}
{"paper_id": "p2", "citation_count": 100, "datasets": ["d3"], "citations": []}
{"paper_id": "p3", "citation_count": 10, "datasets": ["d1"], "citations": []}
{"paper_id": "p4", "citation_count": 250, "datasets": ["d4"], "citations": ["p1"]}
{"paper_id": "p5", "citation_count": 300, "datasets": ["d2"], "citations": ["p4", "p2"]}
EOF

    chmod -R 777 /home/user
