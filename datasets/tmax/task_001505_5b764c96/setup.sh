#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs("/home/user", exist_ok=True)
db_path = "/home/user/backups.db"

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
cur.execute("CREATE TABLE edges (source TEXT, target TEXT, cost INTEGER)")

nodes = [
    (1, 'ROOT'),
    (2, 'A'),
    (3, 'B'),
    (4, 'C'),
    (5, 'TARGET'),
    (6, 'CRITICAL')
]
cur.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)

edges = [
    ('ROOT', 'A', 10),
    ('A', 'B', 5),
    ('B', 'TARGET', 15),
    ('ROOT', 'C', 20),
    ('C', 'TARGET', 5),
    ('ROOT', 'CRITICAL', 1),
    ('A', 'CRITICAL', 1),
    ('B', 'CRITICAL', 1),
    ('C', 'CRITICAL', 1)
]
cur.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

# Create an index (simulating the one that the agent shouldn't query directly)
cur.execute("CREATE INDEX idx_edges_source ON edges(source)")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
