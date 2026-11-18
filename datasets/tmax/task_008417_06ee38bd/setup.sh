#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import json
import sqlite3

os.makedirs('/home/user/data', exist_ok=True)

# 1. Setup SQLite Database
db_path = '/home/user/data/finance.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE transactions (
    tx_id TEXT PRIMARY KEY,
    sender TEXT,
    receiver TEXT,
    amount REAL,
    status TEXT
)
''')

cursor.execute('''
CREATE TABLE audit_log (
    log_id INTEGER PRIMARY KEY AUTOINCREMENT,
    tx_id TEXT,
    action TEXT,
    timestamp DATETIME
)
''')

transactions = [
    ('tx1', 'emp_A', 'emp_B', 100.0, 'flagged'),
    ('tx2', 'emp_B', 'emp_C', 250.0, 'flagged'),
    ('tx3', 'emp_C', 'emp_D', 300.0, 'completed'),
    ('tx4', 'emp_D', 'emp_A', 150.0, 'flagged'),
    ('tx5', 'emp_E', 'emp_A', 400.0, 'flagged'),
    ('tx6', 'emp_F', 'emp_E', 50.0, 'flagged')
]
cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)

audit_logs = [
    ('tx1', 'created', '2023-10-01 10:00:00'),
    ('tx2', 'created', '2023-10-01 10:05:00'),
    ('tx2', 'deleted', '2023-10-02 11:00:00'),
    ('tx3', 'created', '2023-10-01 10:10:00'),
    ('tx4', 'created', '2023-10-01 10:15:00'),
    ('tx5', 'created', '2023-10-01 10:20:00'),
    ('tx6', 'created', '2023-10-01 10:25:00'),
]
cursor.executemany('INSERT INTO audit_log (tx_id, action, timestamp) VALUES (?, ?, ?)', audit_logs)

conn.commit()
conn.close()

# 2. Setup JSON Comms
comms = [
    {"source": "emp_A", "target": "emp_B", "channel": "email"},
    {"source": "emp_B", "target": "emp_C", "channel": "slack"},
    {"source": "emp_D", "target": "emp_A", "channel": "email"},
    {"source": "emp_E", "target": "emp_A", "channel": "slack"},
    {"source": "emp_A", "target": "emp_E", "channel": "email"},
    {"source": "emp_D", "target": "emp_B", "channel": "slack"},
    {"source": "emp_F", "target": "emp_E", "channel": "slack"},
    {"source": "emp_F", "target": "emp_A", "channel": "email"}
]

with open('/home/user/data/comms.json', 'w') as f:
    json.dump(comms, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
