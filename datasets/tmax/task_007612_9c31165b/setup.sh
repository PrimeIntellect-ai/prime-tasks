#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/data.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE events(id INTEGER PRIMARY KEY, user_id INTEGER, event_type TEXT, timestamp INTEGER)')
c.execute('CREATE INDEX idx_user_event ON events(user_id, event_type)')

users = [101, 102, 103, 104, 105, 201, 202]
for u in users:
    c.execute('INSERT INTO events(user_id, event_type, timestamp) VALUES (?, ?, ?)', (u, 'login', 1000))
    c.execute('INSERT INTO events(user_id, event_type, timestamp) VALUES (?, ?, ?)', (u, 'purchase', 1005))
    c.execute('INSERT INTO events(user_id, event_type, timestamp) VALUES (?, ?, ?)', (u, 'login', 1010))
    c.execute('INSERT INTO events(user_id, event_type, timestamp) VALUES (?, ?, ?)', (u, 'logout', 1015))
    if u > 200:
        c.execute('INSERT INTO events(user_id, event_type, timestamp) VALUES (?, ?, ?)', (u, 'purchase', 1020))

conn.commit()

c.execute("SELECT rootpage FROM sqlite_master WHERE type='index' AND name='idx_user_event'")
rootpage = c.fetchone()[0]
conn.close()

# Corrupt the index page
page_size = 4096
with open(db_path, 'r+b') as f:
    f.seek((rootpage - 1) * page_size)
    f.write(b'\x00' * 100)
EOF

    python3 /tmp/setup_db.py

    cat << 'EOF' > /home/user/input.csv
user_id
102
104
201
202
EOF

    chmod -R 777 /home/user
    chmod 444 /home/user/data.db
