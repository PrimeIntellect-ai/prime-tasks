#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Create SQLite DB
db_path = '/home/user/employees.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE org (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')

employees = [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'David', 2),
    (5, 'Eve', 2),
    (6, 'Frank', 3),
    (7, 'Grace', 5)
]

c.executemany('INSERT INTO org VALUES (?, ?, ?)', employees)
conn.commit()
conn.close()

# 2. Create permissions.json
permissions = {
    "1": ["RES_A"],
    "2": ["RES_B"],
    "3": ["RES_C"],
    "4": ["RES_D"],
    "5": ["RES_B", "RES_E"],
    "6": ["RES_F"],
    "7": ["RES_G", "RES_H"]
}

with open('/home/user/permissions.json', 'w') as f:
    json.dump(permissions, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
