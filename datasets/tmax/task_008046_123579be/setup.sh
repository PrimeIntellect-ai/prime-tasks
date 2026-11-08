#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, category TEXT)")
c.execute("CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL)")

# Insert nodes
nodes = [
    (42, 'root', 'main'),
    (101, 'child1', 'sub'),
    (102, 'child2', 'sub'),
    (201, 'grandchild1', 'leaf'),
    (202, 'grandchild2', 'leaf'),
    (301, 'greatgrandchild1', 'leaf'),
    (401, 'too_deep', 'hidden'),
    (999, 'unconnected', 'none')
]
c.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

# Insert edges
edges = [
    (42, 101, 1.0),
    (42, 102, 1.5),
    (101, 201, 2.0),
    (102, 202, 0.5),
    (202, 301, 1.2),
    (301, 401, 3.0),
    (999, 101, 1.0)
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
