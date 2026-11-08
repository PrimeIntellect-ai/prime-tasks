#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/graph_backup.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE nodes (node_id INTEGER PRIMARY KEY)")
cursor.execute("CREATE TABLE edges (edge_id INTEGER PRIMARY KEY, source_id INTEGER, target_id INTEGER, rel_type TEXT)")

nodes = [(1,), (2,), (3,), (4,), (5,)]
cursor.executemany("INSERT INTO nodes (node_id) VALUES (?)", nodes)

edges = [
    (1, 1, 2, "KNOWS"),
    (2, 2, 3, "LIKES"),
    (3, 3, 99, "FOLLOWS"),
    (4, 4, 100, "KNOWS"),
    (5, 5, 1, "LIKES"),
    (6, 1, 88, "FOLLOWS"),
    (7, 99, 1, "KNOWS")
]
cursor.executemany("INSERT INTO edges (edge_id, source_id, target_id, rel_type) VALUES (?, ?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
