#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious.csv
entity_id,risk_score
E101,85
E205,90
E309,75
E411,99
EOF

    cat << 'EOF' > /home/user/graph_results.jsonl
{"entity_id": "E101", "cycle_lengths": [3, 4, 3]}
{"entity_id": "E205", "cycle_lengths": [2]}
{"entity_id": "E309", "cycle_lengths": []}
{"entity_id": "E411", "cycle_lengths": [4, 4, 4, 4, 1]}
EOF

    chmod -R 777 /home/user
