#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json

os.makedirs('/home/user', exist_ok=True)

reviews = [
    {"user_id": 101, "timestamp": "05-Jan-2023 14:00:00", "text": "Great app! \\\\u2764"},
    {"user_id": 102, "timestamp": "2023/01/05 15:30:00", "text": "Broken \\\\uD83D\\\\uDE2D"},
    {"user_id": 103, "timestamp": "05-01-2023 16:45:00", "text": "Me gusta la aplicaci\\\\u00f3n"},
    {"user_id": 104, "timestamp": "05-Jan-2023 17:00:00", "text": "No logs for me \\\\u263A"}
]

with open('/home/user/reviews_raw.jsonl', 'w') as f:
    for r in reviews:
        f.write(json.dumps(r) + '\n')

csv_content = """user_id,log_epoch,action
101,1672927350,login
101,1672927500,click
102,1672932660,update
103,1672937100,logout
105,1672938000,login
"""
with open('/home/user/server_logs.csv', 'w') as f:
    f.write(csv_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
