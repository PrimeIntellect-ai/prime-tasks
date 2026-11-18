#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_math.jsonl
{"id": 1, "expr": "2 + 3 * 4"}
{"id": 2, "expr": "( 8 / 2 ) - 1"}
{"id": 3, "expr": "5 * 5"}
{"id": 4, "expr": "1 + 1"}
EOF

    chmod -R 777 /home/user
