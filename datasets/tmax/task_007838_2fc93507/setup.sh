#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/concepts.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE concepts (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE dependencies (source INTEGER, target INTEGER, weight REAL)')

for i in range(1, 101):
    c.execute('INSERT INTO concepts (id, name) VALUES (?, ?)', (i, f'Concept {i}'))

random.seed(42)
for i in range(1, 101):
    for j in range(1, 101):
        if i != j and random.random() < 0.05:
            c.execute('INSERT INTO dependencies (source, target, weight) VALUES (?, ?, ?)', (i, j, random.uniform(5.0, 15.0)))

# Guaranteed shortest path
path = [(15, 33, 1.0), (33, 71, 1.0), (71, 85, 1.0)]
for u, v, w in path:
    c.execute('INSERT INTO dependencies (source, target, weight) VALUES (?, ?, ?)', (u, v, w))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
