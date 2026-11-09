#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc sqlite3
    pip3 install pytest

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_metrics.jsonl
{"record_id": "rec_001", "features": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]}
{"record_id": "rec_002", "features": [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]}
{"record_id": "rec_003", "features": [1.0, 2.0]} 
{"record_id": "", "features": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]}
{"record_id": "rec_004", "features": [-1.0, -2.0, -3.0, -4.0, -5.0, -6.0, -7.0, -8.0]}
{"record_id": "rec_005", "features": [10.2, 3.4, 5.6, 7.8, 9.0, 1.2, 3.4, 5.6]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
