#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

# Create DB
db_path = '/home/user/communications.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('CREATE TABLE system_users (uid INTEGER PRIMARY KEY, handle TEXT)')
cur.execute('CREATE TABLE message_meta (msg_id INTEGER PRIMARY KEY, content TEXT)')
cur.execute('CREATE TABLE event_links (event_id INTEGER PRIMARY KEY, msg_id INTEGER, source_uid INTEGER, target_uid INTEGER)')

users = [
    (1, 'alice'),
    (2, 'bob'),
    (3, 'charlie'),
    (4, 'diana'),
    (5, 'eve')
]
cur.executemany('INSERT INTO system_users VALUES (?, ?)', users)

links = [
    (1, 1, 1, 2),
    (2, 2, 1, 3),
    (3, 3, 2, 1),
    (4, 4, 2, 3),
    (5, 5, 2, 3),
    (6, 6, 2, 4),
    (7, 7, 3, 2),
    (8, 8, 4, 2),
    (9, 9, 5, 3)
]

for l in links:
    cur.execute('INSERT INTO message_meta VALUES (?, ?)', (l[1], f"Msg {l[1]}"))
    cur.execute('INSERT INTO event_links VALUES (?, ?, ?, ?)', l)

conn.commit()
conn.close()

# Create schema.json
schema = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "username": {
                "type": "string"
            },
            "communication_score": {
                "type": "integer"
            }
        },
        "required": ["username", "communication_score"],
        "additionalProperties": False
    },
    "maxItems": 3
}

with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
