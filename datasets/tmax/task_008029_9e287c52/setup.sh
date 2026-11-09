#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/graph.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT)')
c.execute('CREATE TABLE edges (source INTEGER, target INTEGER)')

# Insert some dummy nodes to make the DB non-empty
for i in range(1000):
    c.execute('INSERT INTO nodes (id, label) VALUES (?, ?)', (i, f'Node_{i}'))

# Insert a deterministic graph structure
edges = [
    (42, 100), (42, 101),
    (100, 200), (100, 201), (101, 202),
    (200, 300), (202, 301),
    (300, 400),
    # Random disconnected edges
    (1, 2), (2, 3), (101, 100)
]
c.executemany('INSERT INTO edges (source, target) VALUES (?, ?)', edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
