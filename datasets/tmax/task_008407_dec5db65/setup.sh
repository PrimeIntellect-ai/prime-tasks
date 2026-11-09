#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/system_graph.db')
c = conn.cursor()
c.execute('CREATE TABLE tbl_metadata (id INTEGER, info TEXT)')
c.execute('CREATE TABLE hidden_rels (u INTEGER, v INTEGER)')

# Insert edges
random.seed(123)
edges = set()
for _ in range(500):
    u = random.randint(1, 100)
    v = random.randint(1, 100)
    if u != v:
        edges.add((u, v))

# Ensure node 42 has some edges
edges.add((42, 10))
edges.add((42, 11))
edges.add((12, 42))

for u, v in edges:
    c.execute('INSERT INTO hidden_rels (u, v) VALUES (?, ?)', (u, v))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
