#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json

conn = sqlite3.connect('/home/user/social_network.db')
c = conn.cursor()
c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, profile_json TEXT)')
c.execute('CREATE TABLE connections (user_id INTEGER, friend_id INTEGER, interaction_score INTEGER)')

# Insert users
users = [10, 15, 20, 42, 99, 88]
for i in users:
    c.execute('INSERT INTO users VALUES (?, ?)', (i, json.dumps({"name": f"User {i}", "age": 20+(i%10)})))

# Insert connections
edges = [
    (10, 15, 10),
    (15, 20, 10),
    (20, 42, 10),
    (10, 99, 5),
    (99, 42, 5),
    (10, 88, 20),
    (88, 42, 20)
]
c.executemany('INSERT INTO connections VALUES (?, ?, ?)', edges)

# Add bad indexes
c.execute('CREATE INDEX idx_bad1 ON connections (interaction_score)')
c.execute('CREATE INDEX idx_bad2 ON connections (user_id, interaction_score)')

conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
