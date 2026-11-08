#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/audit_logs.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE system_access (
    event_id INTEGER PRIMARY KEY,
    actor TEXT,
    target TEXT,
    action_time INTEGER,
    risk REAL,
    context_tag TEXT
)''')

data = [
    (1, 'alice', 'server1', 100, 2.0, 'PROD'),
    (2, 'bob', 'server2', 101, 1.0, 'PROD'),
    (3, 'alice', 'db1', 105, 5.0, 'PROD'),
    (4, 'alice', 'server1', 106, 3.5, 'PROD'), 
    (5, 'bob', 'db1', 110, 4.0, 'PROD'),
    (6, 'bob', 'server3', 115, 6.0, 'PROD'), 
    (7, 'charlie', 'server1', 120, 8.0, 'PROD'),
    (8, 'charlie', 'db1', 121, 1.0, 'PROD'),
    (9, 'alice', 'db2', 125, 1.0, 'PROD'), 
    (10, 'dave', 'server1', 130, 9.0, 'DEV'),
    (11, 'dave', 'server2', 131, 2.0, 'DEV'),
    (12, 'eve', 'server3', 140, 1.5, 'PROD'),
    (13, 'eve', 'server1', 141, 1.5, 'PROD'),
    (14, 'eve', 'db2', 142, 1.5, 'PROD'),
    (15, 'eve', 'server2', 143, 1.5, 'PROD')
]

c.executemany('INSERT INTO system_access VALUES (?,?,?,?,?,?)', data)
conn.commit()
conn.close()

os.chmod(db_path, 0o666)
EOF

    python3 /tmp/setup_db.py
    chmod -R 777 /home/user
