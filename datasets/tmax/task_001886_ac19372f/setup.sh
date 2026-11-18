#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import sqlite3
import json

# Setup users.db
conn = sqlite3.connect('/home/user/data/users.db')
c = conn.cursor()
c.execute('CREATE TABLE users (user_id TEXT PRIMARY KEY, region TEXT)')
users = [
    ('u1', 'NA'),
    ('u2', 'NA'),
    ('u3', 'EU'),
    ('u4', 'EU'),
    ('u5', 'ASIA'),
    ('u6', 'ASIA')
]
c.executemany('INSERT INTO users VALUES (?, ?)', users)
conn.commit()
conn.close()

# Setup events.jsonl
events = [
    {"user_id": "u1", "event_type": "level_complete", "score": 10},
    {"user_id": "u1", "event_type": "login", "score": 0},
    {"user_id": "u1", "event_type": "level_complete", "score": 50},
    {"user_id": "u1", "event_type": "level_complete", "score": 20},
    {"user_id": "u1", "event_type": "level_complete", "score": 30},
    {"user_id": "u2", "event_type": "level_complete", "score": 40},
    {"user_id": "u2", "event_type": "level_complete", "score": 40},
    {"user_id": "u3", "event_type": "level_complete", "score": 100},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u5", "event_type": "level_complete", "score": 200},
    {"user_id": "u6", "event_type": "login", "score": 10}
]

with open('/home/user/data/events.jsonl', 'w') as f:
    for e in events:
        f.write(json.dumps(e) + '\n')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
