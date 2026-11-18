#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.jsonl
{"id": "doc1", "description": "Machine learning is a subfield of artificial intelligence."}
{"id": "doc2", "description": "Data science involves statistics and data analysis."}
{"id": "doc3", "description": "An algorithm is a step-by-step procedure for calculations."}
{"id": "doc4", "description": "Deep learning models require a lot of data and machine power."}
{"id": "doc5", "description": "Data data data science science."}
{"invalid_id": "doc6", "text": "Missing description field"}
{"id": "doc7", "description": "learning algorithm data machine science"}
EOF

    chmod -R 777 /home/user
