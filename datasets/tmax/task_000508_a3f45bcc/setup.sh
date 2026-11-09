#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = '/home/user/transactions.db'
json_path = '/home/user/processes.json'

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE locks (lock_id INTEGER PRIMARY KEY, process_id INTEGER, resource_id INTEGER, status TEXT)')

locks_data = [
    (1, 101, 10, 'GRANTED'),
    (2, 101, 20, 'WAITING'),
    (3, 102, 20, 'GRANTED'),
    (4, 102, 30, 'WAITING'),
    (5, 103, 30, 'GRANTED'),
    (6, 103, 10, 'WAITING'),
    (7, 201, 40, 'GRANTED'),
    (8, 201, 50, 'WAITING'),
    (9, 202, 50, 'GRANTED'),
    (10, 202, 40, 'WAITING'),
    (11, 301, 60, 'GRANTED'),
    (12, 302, 60, 'WAITING')
]

c.executemany('INSERT INTO locks VALUES (?, ?, ?, ?)', locks_data)
conn.commit()
conn.close()

processes_data = [
    {"process_id": 101, "owner": "user", "priority": 1},
    {"process_id": 102, "owner": "user", "priority": 2},
    {"process_id": 103, "owner": "user", "priority": 1},
    {"process_id": 201, "owner": "user", "priority": 3},
    {"process_id": 202, "owner": "system", "priority": 9},
    {"process_id": 301, "owner": "user", "priority": 1},
    {"process_id": 302, "owner": "user", "priority": 1}
]

with open(json_path, 'w') as f:
    json.dump(processes_data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
