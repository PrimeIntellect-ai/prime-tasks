#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/data1.jsonl
{"id": "101", "user": "alice", "text": "Great service!"}
{"id": "102", "user": "bob", "text": "I love the new features."}
EOF

    cat << 'EOF' > /home/user/raw_data/data2.jsonl
{"id": "201", "user": "charlie", "text": "Not bad."}
{"id": "202", "user": "diana", "text": "Broken unicode \u28ZZ here."}
{"id": "203", "user": "eve", "text": "All good now."}
EOF

    cat << 'EOF' > /home/user/raw_data/data3.jsonl
{"id": "301", "user": "frank", "text": "Missing escape \u1"}
{"id": "302", "user": "grace", "text": "Perfect!"}
EOF

    chmod -R 777 /home/user
