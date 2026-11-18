#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/graph_backup.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, node_type TEXT, status TEXT)')
cur.execute('CREATE TABLE edges (source_id INTEGER, target_id INTEGER, relation TEXT)')

nodes = [
    (1, 'web_api', 'service', 'active'),
    (2, 'user_db', 'storage', 'active'),
    (3, 'cache_layer', 'storage', 'degraded'),
    (4, 'auth_service', 'service', 'active'),
    (5, 'log_db', 'storage', 'inactive'),
    (6, 'background_worker', 'service', 'active'),
    (7, 'payment_gateway', 'external', 'active')
]

cur.executemany('INSERT INTO nodes VALUES (?, ?, ?, ?)', nodes)

edges = [
    (1, 2, 'depends_on'),
    (1, 3, 'depends_on'),
    (4, 2, 'depends_on'),
    (6, 5, 'depends_on'),
    (1, 4, 'calls'),
    (4, 7, 'calls'),
    (6, 2, 'reads_from')
]

cur.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
