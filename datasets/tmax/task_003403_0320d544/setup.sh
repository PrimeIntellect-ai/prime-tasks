#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/network.db')
c = conn.cursor()

c.execute('''
CREATE TABLE edges (
    id INTEGER PRIMARY KEY,
    src TEXT,
    dst TEXT,
    cost INTEGER,
    updated_at INTEGER
)
''')

edges_data = [
    (1, 'CORE_1', 'DIST_1', 1, 1000),
    (2, 'CORE_1', 'DIST_1', 10, 2000),
    (3, 'CORE_1', 'DIST_2', 15, 2000),
    (4, 'DIST_1', 'EDGE_7', 20, 2000),
    (5, 'DIST_2', 'EDGE_7', 5, 2000),
    (6, 'CORE_1', 'DIST_3', 5, 2000),
    (7, 'DIST_3', 'DIST_4', 5, 2000),
    (8, 'DIST_4', 'EDGE_7', 2, 1000),
    (9, 'DIST_4', 'EDGE_7', 50, 2000)
]

c.executemany('INSERT INTO edges VALUES (?,?,?,?,?)', edges_data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
