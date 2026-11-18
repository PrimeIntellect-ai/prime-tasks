#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
import os

db_path = "/home/user/graph_data.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE nodes (id INT, label TEXT, property TEXT)")
c.execute("CREATE TABLE relations (src INT, dst INT, type TEXT)")

# Insert nodes
nodes = []
for i in range(1, 1001):
    prop = 'target' if i in [10, 20, 30, 40, 50, 60] else 'background'
    nodes.append((i, f"Node_{i}", prop))

c.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

# Insert random edges
edges = set()
for _ in range(3000):
    u = random.randint(1, 1000)
    v = random.randint(1, 1000)
    if u != v:
        edges.add((u, v, 'interaction'))

# Insert explicit motifs (Feed-Forward Loops)
# Motif 1: 10 -> 20, 20 -> 30, 10 -> 30
edges.add((10, 20, 'interaction'))
edges.add((20, 30, 'interaction'))
edges.add((10, 30, 'interaction'))

# Motif 2: 10 -> 40, 40 -> 50, 10 -> 50
edges.add((10, 40, 'interaction'))
edges.add((40, 50, 'interaction'))
edges.add((10, 50, 'interaction'))

# Motif 3: 20 -> 40, 40 -> 30, 20 -> 30
edges.add((20, 40, 'interaction'))
edges.add((40, 30, 'interaction'))
edges.add((20, 30, 'interaction'))

# Decoy (Missing A->C)
edges.add((50, 60, 'interaction'))
edges.add((60, 10, 'interaction'))

c.executemany("INSERT INTO relations VALUES (?, ?, ?)", list(edges))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
