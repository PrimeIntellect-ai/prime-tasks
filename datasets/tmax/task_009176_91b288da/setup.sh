#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = "/home/user/network.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT)")
cur.execute("CREATE TABLE follows (follower_id INTEGER, followee_id INTEGER, created_at DATETIME)")
cur.execute("CREATE TABLE active_follows (follower_id INTEGER, followee_id INTEGER)")

random.seed(42)
users = []
for i in range(1, 101):
    username = f"user_{i}"
    users.append((i, username))
    cur.execute("INSERT INTO users VALUES (?, ?)", (i, username))

follows = set()
while len(follows) < 500:
    u1 = random.randint(1, 100)
    u2 = random.randint(1, 100)
    if u1 != u2:
        follows.add((u1, u2))

for u1, u2 in follows:
    cur.execute("INSERT INTO follows VALUES (?, ?, '2023-01-01 12:00:00')", (u1, u2))
    cur.execute("INSERT INTO active_follows VALUES (?, ?)", (u1, u2))

stale = []
while len(stale) < 100:
    u1 = random.randint(1, 120)
    u2 = random.randint(1, 120)
    if (u1, u2) not in follows:
        stale.append((u1, u2))

for u1, u2 in stale:
    cur.execute("INSERT INTO active_follows VALUES (?, ?)", (u1, u2))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
