#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/kg_data.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (
    id INTEGER, label TEXT, valid_from INTEGER, valid_to INTEGER
)''')

c.execute('''CREATE TABLE edges (
    source_id INTEGER, target_id INTEGER, type TEXT, valid_from INTEGER, valid_to INTEGER
)''')

# Timestamp to check against: 1700000000

# Nodes
nodes_data = [
    (1, 'EntityA', 1600000000, 2000000000), # Active
    (2, 'EntityB', 1650000000, 2000000000), # Active
    (3, 'EntityC', 1600000000, 2000000000), # Active
    (4, 'EntityD', 1690000000, 2000000000), # Active
    (5, 'EntityE', 1500000000, 1650000000), # Stale (valid_to < 1700000000)
    (6, 'EntityF', 1600000000, 2000000000), # Active
]
c.executemany("INSERT INTO nodes VALUES (?,?,?,?)", nodes_data)

# Edges (9 total to match test expectations)
edges_data = [
    # Node 1 active edges
    (1, 2, 'REL', 1650000000, 2000000000),
    (1, 3, 'REL', 1650000000, 2000000000),
    (1, 4, 'REL', 1695000000, 2000000000),

    # Node 4 active edges
    (4, 1, 'REL', 1695000000, 2000000000),
    (4, 2, 'REL', 1695000000, 2000000000),
    (4, 3, 'REL', 1695000000, 2000000000),

    # Edge to a stale node (5).
    (2, 5, 'REL', 1600000000, 2000000000),

    # Valid edge for Node 6
    (3, 6, 'REL', 1600000000, 2000000000),
    (6, 2, 'REL', 1600000000, 2000000000),
]
c.executemany("INSERT INTO edges VALUES (?,?,?,?,?)", edges_data)

conn.commit()
conn.close()

os.chmod(db_path, 0o666)
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
