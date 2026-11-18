#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/sys_graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE t_ent_99 (ent_id INTEGER PRIMARY KEY, ent_name TEXT)')
c.execute('CREATE TABLE t_rel_88 (src INTEGER, dst INTEGER, cost INTEGER)')

nodes = {
    1: 'AlphaCore',
    2: 'NodeB',
    3: 'NodeC',
    4: 'NodeD',
    5: 'NodeE',
    6: 'OmegaRelay',
    7: 'Decoy1',
    8: 'Decoy2'
}

for k, v in nodes.items():
    c.execute('INSERT INTO t_ent_99 (ent_id, ent_name) VALUES (?, ?)', (k, v))

edges = [
    (1, 2, 5),
    (2, 3, 10),
    (3, 6, 5),
    (1, 4, 2),
    (4, 5, 3),
    (5, 6, 12),
    (2, 5, 1),
    (1, 7, 100),
    (7, 8, 10),
    (8, 6, 10)
]

for src, dst, cost in edges:
    c.execute('INSERT INTO t_rel_88 (src, dst, cost) VALUES (?, ?, ?)', (src, dst, cost))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
