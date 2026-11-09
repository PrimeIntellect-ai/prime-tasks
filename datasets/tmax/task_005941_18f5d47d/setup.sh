#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo cron
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_logs.jsonl
{"id": 1, "temp_f": 104.0, "notes": "normal log"}
{"id": 2, "temp_f": 50.0, "notes": "malformed \u001 sequence"}
{"id": 3, "temp_f": 86.0, "notes": "all good here"}
{"id": 4, "temp_f": 32.0, "notes": "another \u001 issue"}
{"id": 5, "temp_f": 98.6, "notes": "human body temp"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
