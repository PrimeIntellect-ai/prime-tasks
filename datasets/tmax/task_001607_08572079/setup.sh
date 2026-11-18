#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/knowledge.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE _node_data (node_id INTEGER PRIMARY KEY, node_name TEXT)')
c.execute('CREATE TABLE _edge_data (src INTEGER, dst INTEGER)')

nodes = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta', 'Omega', 'Theta']
for i, n in enumerate(nodes, 1):
    c.execute('INSERT INTO _node_data VALUES (?, ?)', (i, n))

edges = [
    (1, 2), # Alpha -> Beta
    (1, 3), # Alpha -> Gamma
    (1, 8), # Alpha -> Theta
    (2, 6), # Beta -> Zeta
    (3, 6), # Gamma -> Zeta
    (8, 6), # Theta -> Zeta
    (6, 7), # Zeta -> Omega
    (3, 4), # Gamma -> Delta
    (4, 5), # Delta -> Epsilon
    (5, 7)  # Epsilon -> Omega
]

for u, v in edges:
    c.execute('INSERT INTO _edge_data VALUES (?, ?)', (u, v))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
