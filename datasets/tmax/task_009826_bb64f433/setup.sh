#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/hierarchy.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    type TEXT,
    local_size INTEGER
)''')

c.execute('''CREATE TABLE quotas (
    node_id INTEGER PRIMARY KEY,
    max_size INTEGER
)''')

nodes_data = [
    (1, None, 'root', 'dir', 10),
    (2, 1, 'var', 'dir', 5),
    (3, 2, 'log', 'dir', 20),
    (4, 3, 'syslog', 'file', 50),
    (5, 1, 'home', 'dir', 5),
    (6, 5, 'user', 'dir', 10),
    (7, 6, 'data.db', 'file', 100),
    (8, 2, 'tmp', 'dir', 5)
]

quotas_data = [
    (1, 500),
    (2, 50),
    (3, 100),
    (5, 100),
    (6, 150)
]

c.executemany('INSERT INTO nodes VALUES (?,?,?,?,?)', nodes_data)
c.executemany('INSERT INTO quotas VALUES (?,?)', quotas_data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
