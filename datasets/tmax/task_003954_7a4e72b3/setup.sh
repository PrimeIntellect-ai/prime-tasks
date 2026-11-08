#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import os

db_path = '/home/user/topology.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (id INTEGER PRIMARY KEY, role TEXT)''')
c.execute('''CREATE TABLE edges (src INTEGER, dst INTEGER, latency INTEGER)''')
c.execute('''CREATE INDEX idx_edges_src ON edges(src)''')

# Insert nodes
nodes = [
    (1, 'compute'),
    (2, 'compute'),
    (3, 'compute'),
    (4, 'compute'),
    (5, 'compute'),
    (6, 'storage'),
    (7, 'storage'),
    (8, 'router')
]
c.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)

# Insert edges
edges = [
    # Triangle 1 (Compute only) 1->2->3->1 (Latency: 10 + 20 + 30 = 60)
    (1, 2, 10),
    (2, 3, 20),
    (3, 1, 30),

    # Triangle 2 (Compute only) 2->4->5->2 (Latency: 5 + 5 + 5 = 15) -> MINIMUM
    (2, 4, 5),
    (4, 5, 5),
    (5, 2, 5),

    # Triangle 3 (Compute only) 1->4->3->1 (Latency: 50 + 50 + 50 = 150)
    (1, 4, 50),
    (4, 3, 50),

    # Triangle 4 (Mixed - must be ignored) 1->6->2->1 (Latency: 1 + 1 + 1 = 3)
    (1, 6, 1),
    (6, 2, 1),
    # 2->1 is not needed, we can use 2->3->1 path or whatever, let's explicitly make a cycle
    (2, 1, 1), 

    # Triangle 5 (Storage only - must be ignored) 6->7->8->6 (Latency: 2 + 2 + 2 = 6)
    (6, 7, 2),
    (7, 8, 2),
    (8, 6, 2)
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
