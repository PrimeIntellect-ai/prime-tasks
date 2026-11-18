#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

conn = sqlite3.connect('/home/user/company.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER)')
employees = [
    (1, 'Alice (CEO)', None, 1),
    (2, 'Bob (VP Eng)', 1, 2),
    (3, 'Charlie (VP Sales)', 1, 3),
    (4, 'David (Eng)', 2, 2),
    (5, 'Eve (Eng)', 2, 2),
    (6, 'Frank (Sales)', 3, 3),
    (7, 'Grace (HR)', 1, 4),
    (8, 'Heidi (HR Intern)', 7, 4),
    (9, 'Ivan (Eng Intern)', 4, 2)
]
c.executemany('INSERT INTO employees VALUES (?,?,?,?)', employees)
conn.commit()
conn.close()

departments = [
    {"dept_id": 1, "dept_name": "Executive", "budget": 1000000},
    {"dept_id": 2, "dept_name": "Engineering", "budget": 800000},
    {"dept_id": 3, "dept_name": "Sales", "budget": 400000},
    {"dept_id": 4, "dept_name": "Human Resources", "budget": 600000}
]

with open('/home/user/departments.jsonl', 'w') as f:
    for d in departments:
        f.write(json.dumps(d) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
