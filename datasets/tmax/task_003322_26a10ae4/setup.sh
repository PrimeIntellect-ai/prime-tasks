#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import json

raw_data = [
    # User B: out of order
    {"user_id": "user_b", "timestamp": 1005, "text": "   Extra \t spaces\nhere  "},
    {"user_id": "user_b", "timestamp": 1001, "text": "Hello"},
    # User A: unnormalized diacritics
    {"user_id": "user_a", "timestamp": 2000, "text": "Ame\u0301lie"}, # e + combining acute
    {"user_id": "user_a", "timestamp": 2010, "text": "Am\u00e9lie"}, # precomposed é
    {"user_id": "user_a", "timestamp": 2020, "text": "H\u00f4tel"}, # precomposed ô
    {"user_id": "user_a", "timestamp": 2030, "text": "Caf\u00e9"}, # precomposed é
]

with open('/home/user/raw_messages.jsonl', 'w', encoding='utf-8') as f:
    for record in raw_data:
        f.write(json.dumps(record) + '\n')
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
