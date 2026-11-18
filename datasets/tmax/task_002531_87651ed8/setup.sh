#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/audit_data.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE employees (emp_id INTEGER, name TEXT, department_id INTEGER)')
c.execute('CREATE TABLE systems (sys_id INTEGER, sys_name TEXT, owning_dept_id INTEGER)')
c.execute('CREATE TABLE exceptions (emp_id INTEGER, sys_id INTEGER)')
c.execute('CREATE TABLE access_logs (log_id INTEGER, emp_id INTEGER, sys_id INTEGER, timestamp TEXT)')

c.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
    (1, 'Alice', 10),
    (2, 'Bob', 20),
    (3, 'Charlie', 30),
    (4, 'Diana', 10)
])

c.executemany('INSERT INTO systems VALUES (?, ?, ?)', [
    (100, 'HR_Portal', 10),
    (200, 'IT_Admin', 20),
    (300, 'Finance_DB', 30)
])

c.executemany('INSERT INTO exceptions VALUES (?, ?)', [
    (2, 100)
])

logs = [
    (1, 1, 100, '2023-01-01'),
    (2, 2, 200, '2023-01-01'),
    (3, 3, 300, '2023-01-01'),
    (4, 2, 100, '2023-01-02'),
    (5, 1, 200, '2023-01-03'),
    (6, 1, 200, '2023-01-04'),
    (7, 1, 300, '2023-01-05'),
    (8, 3, 100, '2023-01-06'),
    (9, 3, 200, '2023-01-07')
]

c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
