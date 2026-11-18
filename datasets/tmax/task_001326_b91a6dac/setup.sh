#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/db_topology.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE,
    node_type TEXT
)
''')

cursor.execute('''
CREATE TABLE edges (
    source_id INTEGER,
    target_id INTEGER,
    latency_ms INTEGER,
    connection_type TEXT,
    FOREIGN KEY(source_id) REFERENCES nodes(id),
    FOREIGN KEY(target_id) REFERENCES nodes(id)
)
''')

nodes = [
    (1, 'API_Gateway', 'service'),
    (2, 'Auth_Service', 'service'),
    (3, 'Cache_Layer', 'cache'),
    (4, 'User_ReadReplica', 'database'),
    (5, 'User_Master', 'database'),
    (6, 'Billing_Service', 'service'),
    (7, 'Message_Queue', 'queue')
]
cursor.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

edges = [
    (1, 2, 15, 'rpc'),
    (1, 3, 5, 'tcp'),
    (2, 4, 25, 'sql'),
    (3, 4, 20, 'sql'),
    (4, 5, 8, 'replication'),
    (1, 6, 40, 'rpc'),
    (6, 5, 2, 'sql'),
    (1, 7, 10, 'amqp'),
    (7, 5, 12, 'worker')
]
cursor.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
