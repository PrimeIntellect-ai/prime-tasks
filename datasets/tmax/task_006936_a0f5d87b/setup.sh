#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/etl_graph.db')
c = conn.cursor()

c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE edges (source INTEGER, target INTEGER, latency INTEGER, created_at INTEGER)")

# Nodes
nodes = [
    (1, 'Extract'),
    (2, 'Clean'),
    (3, 'Join'),
    (4, 'Aggregate'),
    (5, 'Load')
]
c.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)

# Edges (includes stale rows)
edges = [
    (1, 2, 100, 1000),
    (1, 2, 5, 2000),
    (2, 3, 10, 1500),
    (1, 3, 50, 1000),
    (3, 4, 15, 1000),
    (4, 5, 5, 1000),
    (2, 4, 100, 1000),
    (2, 4, 20, 2000)
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
chmod 666 /home/user/etl_graph.db

chmod -R 777 /home/user
