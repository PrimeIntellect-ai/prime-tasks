#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 << 'EOF'
import sqlite3
import json
import os

db_path = "/home/user/employees.db"
json_path = "/home/user/transfers.json"

if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department_id INTEGER)")

departments = [
    (1, 'Sales'),
    (2, 'Engineering'),
    (3, 'HR'),
    (4, 'Executive')
]

employees = [
    (1, 'Alice', 1),
    (2, 'Bob', 1),
    (3, 'Charlie', 2),
    (4, 'David', 2),
    (5, 'Eve', 2),
    (6, 'Frank', 3),
    (7, 'Grace', 3),
    (8, 'Heidi', 4),
    (9, 'Ivan', 4),
    (10, 'Judy', 1)
]

c.executemany("INSERT INTO departments VALUES (?, ?)", departments)
c.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)
conn.commit()
conn.close()

transfers = [
    {"source_emp_id": 1, "dest_emp_id": 3, "amount": 100, "timestamp": "2023-10-01T10:00:00Z"},
    {"source_emp_id": 3, "dest_emp_id": 4, "amount": 200, "timestamp": "2023-10-01T11:00:00Z"},
    {"source_emp_id": 4, "dest_emp_id": 5, "amount": 300, "timestamp": "2023-10-01T12:00:00Z"},
    {"source_emp_id": 5, "dest_emp_id": 6, "amount": 400, "timestamp": "2023-10-01T13:00:00Z"},
    {"source_emp_id": 2, "dest_emp_id": 1, "amount": 500, "timestamp": "2023-10-01T14:00:00Z"},
    {"source_emp_id": 2, "dest_emp_id": 10, "amount": 600, "timestamp": "2023-10-01T15:00:00Z"},
    {"source_emp_id": 8, "dest_emp_id": 9, "amount": 700, "timestamp": "2023-10-01T16:00:00Z"},
    {"source_emp_id": 9, "dest_emp_id": 8, "amount": 800, "timestamp": "2023-10-01T17:00:00Z"}
]

with open(json_path, 'w') as f:
    json.dump(transfers, f)
EOF

    chmod -R 777 /home/user
