#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/routing.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, status TEXT)''')
c.execute('''CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL)''')

nodes = [
    (1, 'Router_START', 'active'),
    (2, 'Router_A', 'active'),
    (3, 'Router_B', 'offline'),
    (4, 'Router_C', 'active'),
    (5, 'Router_D', 'active'),
    (6, 'Router_END', 'active')
]
c.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

edges = [
    (1, 2, 10.0),
    (1, 4, 15.0),
    (1, 3, 5.0),
    (2, 4, 2.0),
    (2, 5, 8.0),
    (4, 6, 10.0),
    (5, 6, 3.0),
    (4, 5, 1.0),
    (3, 6, 2.0)
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

# Create a bad index
c.execute("CREATE INDEX idx_bad ON edges (weight, target_id)")
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
