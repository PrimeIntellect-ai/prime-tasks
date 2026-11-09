#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reviews_raw.jsonl
{"id": "A1", "user": "U1", "timestamp": "2023-10-01T10:00:00Z", "text": "Café is great!"}
{"id": "A2", "user": "U1", "timestamp": "2023-10-01T10:05:00Z", "text": "Cafe\u0301 is great!  "}
{"id": "B2", "user": "U2", "timestamp": "2023-10-01T09:00:00Z", "text": "hello"}
{"id": "B1", "user": "U2", "timestamp": "2023-10-01T09:00:00Z", "text": "HELLO "}
{"id": "C1", "user": "U3", "timestamp": "2023-10-01T11:00:00Z", "text": "Schön"}
{"id": "C2", "user": "U3", "timestamp": "2023-10-01T10:55:00Z", "text": "schön\n"}
{"id": "D1", "user": "U4", "timestamp": "2023-10-01T08:00:00Z", "text": "Unique review"}
EOF

    chmod -R 777 /home/user
