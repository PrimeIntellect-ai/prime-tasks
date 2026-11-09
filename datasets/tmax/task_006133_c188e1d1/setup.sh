#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/legacy_corp.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create obfuscated table names to force reverse engineering
cursor.execute('''
CREATE TABLE tbl_node_ref (
    id_hash INTEGER PRIMARY KEY,
    parent_hash INTEGER,
    title TEXT,
    full_moniker TEXT
)
''')

cursor.execute('''
CREATE TABLE tbl_metric_log (
    log_seq INTEGER PRIMARY KEY,
    actor_hash INTEGER,
    job_code TEXT,
    duration_hrs INTEGER,
    FOREIGN KEY(actor_hash) REFERENCES tbl_node_ref(id_hash)
)
''')

# Insert Hierarchy
nodes = [
    (1, None, 'CEO', 'John Doe'),
    (2, 1, 'VP', 'Eleanor Vance'),
    (3, 2, 'Director', 'Bob Smith'),
    (4, 3, 'IC', 'Charlie Brown'),
    (5, 2, 'IC', 'Diana Prince'),
    (6, 1, 'VP', 'Alice Cooper'),
    (7, 6, 'IC', 'Eve Adams')
]
cursor.executemany('INSERT INTO tbl_node_ref VALUES (?, ?, ?, ?)', nodes)

# Insert Project Logs
logs = [
    (1, 2, 'PRJ-A', 10),
    (2, 3, 'PRJ-A', 20),
    (3, 3, 'PRJ-B', 15),
    (4, 4, 'PRJ-B', 30),
    (5, 4, 'PRJ-C', 5),
    (6, 5, 'PRJ-A', 5),
    (7, 6, 'PRJ-A', 100),
    (8, 7, 'PRJ-C', 50)
]
cursor.executemany('INSERT INTO tbl_metric_log VALUES (?, ?, ?, ?)', logs)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
