#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Create DB
conn = sqlite3.connect('/home/user/access_logs.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (emp_id INTEGER, name TEXT, dept_id TEXT)')
c.execute('CREATE TABLE logs (log_id INTEGER, emp_id INTEGER, resource_id TEXT, access_time TEXT, status TEXT)')

employees = [
    (1, 'Alice', 'D1'),
    (2, 'Bob', 'D2'),
    (3, 'Charlie', 'D1'),
    (4, 'Dave', 'D3')
]
c.executemany('INSERT INTO employees VALUES (?,?,?)', employees)

logs = [
    (1, 1, 'R1', '2023-10-01', 'SUCCESS'),
    (2, 2, 'R1', '2023-10-01', 'SUCCESS'),
    (3, 2, 'R1', '2023-10-02', 'FAILED'),
    (4, 3, 'R2', '2023-10-03', 'SUCCESS'),
    (5, 3, 'R2', '2023-10-04', 'SUCCESS'),
    (6, 4, 'R3', '2023-10-05', 'SUCCESS'),
    (7, 4, 'R1', '2023-10-06', 'SUCCESS')
]
c.executemany('INSERT INTO logs VALUES (?,?,?,?,?)', logs)
conn.commit()
conn.close()

# 2. Create JSON
resources = [
    {"resource_id": "R1", "allowed_depts": ["D1"]},
    {"resource_id": "R2", "allowed_depts": ["D2", "D3"]},
    {"resource_id": "R3", "allowed_depts": ["D1", "D2", "D3"]}
]
with open('/home/user/resources.json', 'w') as f:
    json.dump(resources, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
