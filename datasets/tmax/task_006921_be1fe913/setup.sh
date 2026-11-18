#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import json
import os

os.makedirs('/home/user/data', exist_ok=True)
conn = sqlite3.connect('/home/user/data/hr.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (id INTEGER, name TEXT, department TEXT)')
c.execute('CREATE TABLE resources (id INTEGER, name TEXT, department_owner TEXT)')

employees = [
    (1, 'Alice', 'Engineering'),
    (2, 'Bob', 'Sales'),
    (3, 'Charlie', 'HR'),
    (4, 'Dave', 'Engineering'),
    (5, 'Eve', 'Marketing')
]
resources = [
    (101, 'SourceCode', 'Engineering'),
    (102, 'CustomerData', 'Sales'),
    (103, 'Payroll', 'HR'),
    (104, 'Campaigns', 'Marketing')
]

c.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)
c.executemany('INSERT INTO resources VALUES (?, ?, ?)', resources)
conn.commit()
conn.close()

access_logs = [
    {"user_id": 1, "resource_id": 101, "timestamp": "T1"},
    {"user_id": 1, "resource_id": 102, "timestamp": "T2"},
    {"user_id": 2, "resource_id": 102, "timestamp": "T3"},
    {"user_id": 2, "resource_id": 103, "timestamp": "T4"},
    {"user_id": 3, "resource_id": 103, "timestamp": "T5"},
    {"user_id": 4, "resource_id": 101, "timestamp": "T6"},
    {"user_id": 4, "resource_id": 103, "timestamp": "T7"},
    {"user_id": 4, "resource_id": 104, "timestamp": "T8"},
    {"user_id": 5, "resource_id": 104, "timestamp": "T9"},
    {"user_id": 5, "resource_id": 101, "timestamp": "T10"},
    {"user_id": 5, "resource_id": 102, "timestamp": "T11"}
]

authorizations = [
    {"user_id": 1, "resource_id": 102},
    {"user_id": 4, "resource_id": 104}
]

with open('/home/user/data/access_logs.json', 'w') as f:
    json.dump(access_logs, f)

with open('/home/user/data/authorizations.json', 'w') as f:
    json.dump(authorizations, f)
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
