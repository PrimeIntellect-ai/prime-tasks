#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Setup SQLite DB
conn = sqlite3.connect('/home/user/users.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)')

users_data = [
    (1, "Alice Smith", "Engineering"),
    (2, "Bob Jones", "Marketing"),
    (3, "Charlie Brown", "Sales"),
    (4, "Diana Prince", "Engineering"),
    (5, "Evan Wright", "HR")
]
cursor.executemany('INSERT INTO users VALUES (?, ?, ?)', users_data)
conn.commit()
conn.close()

# 2. Setup JSONL interactions
interactions_data = [
    {"source_id": 2, "target_id": 1, "interaction_type": "email", "weight": 10},
    {"source_id": 3, "target_id": 1, "interaction_type": "meeting", "weight": 15},
    {"source_id": 4, "target_id": 1, "interaction_type": "chat", "weight": 5},
    {"source_id": 1, "target_id": 4, "interaction_type": "email", "weight": 20},
    {"source_id": 2, "target_id": 4, "interaction_type": "meeting", "weight": 20},
    {"source_id": 5, "target_id": 4, "interaction_type": "email", "weight": 5},
    {"source_id": 1, "target_id": 2, "interaction_type": "chat", "weight": 8},
    {"source_id": 3, "target_id": 2, "interaction_type": "email", "weight": 12},
    {"source_id": 1, "target_id": 3, "interaction_type": "meeting", "weight": 50}
]

with open('/home/user/interactions.jsonl', 'w') as f:
    for interaction in interactions_data:
        f.write(json.dumps(interaction) + '\n')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
