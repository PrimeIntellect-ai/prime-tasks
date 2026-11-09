#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.jsonl
{"ts": 100, "id": "S1", "tk": 300.15, "h": 50.0}
{"ts": 101, "id": "S2", "tk": 298.15, "h": 150.0}
{"ts": 102, "id": "S1", "tk": 303.15, "h": 40.0}
{"ts": 103, "id": "S3", "tk": 0, "h": 40.0}
{"ts": 104, "id": "S2", "tk": 290.15, "h": 10.0}
{"ts": 105, "id": "S1", "tk": 283.15, "h": -5.0}
{"ts": 106, "id": "S1", "tk": 283.15, "h": 20.0}
{"ts": 107, "id": "", "tk": 310.15, "h": 20.0}
{"ts": 108, "id": "S4", "tk": 313.15, "h": 99.9}
EOF

    chmod -R 777 /home/user
