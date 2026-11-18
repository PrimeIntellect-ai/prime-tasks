#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/analyzer

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user/analyzer', exist_ok=True)
db_path = '/home/user/company.db'

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department_id INTEGER)')
c.execute('CREATE TABLE communications (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, bytes INTEGER, timestamp DATETIME)')

# Insert Departments
depts = [(1, 'Engineering'), (2, 'Sales'), (3, 'Marketing')]
c.executemany('INSERT INTO departments VALUES (?,?)', depts)

# Insert Employees
emps = [
    (1, 'Alice', 1), (2, 'Bob', 1), (3, 'Charlie', 1),
    (4, 'Dave', 2), (5, 'Eve', 2), (6, 'Frank', 2), (7, 'Grace', 2),
    (8, 'Heidi', 3), (9, 'Ivan', 3)
]
c.executemany('INSERT INTO employees VALUES (?,?,?)', emps)

# Insert Communications
comms = [
    (1, 1, 2, 100, '2023-01-01'),
    (2, 1, 3, 200, '2023-01-01'),
    (3, 2, 3, 150, '2023-01-01'),
    (4, 3, 4, 500, '2023-01-01'),
    (5, 4, 5, 300, '2023-01-01'),
    (6, 4, 6, 300, '2023-01-01'),
    (7, 4, 7, 400, '2023-01-01'),
    (8, 3, 8, 600, '2023-01-01'),
    (9, 3, 9, 600, '2023-01-01'),
    (10, 2, 8, 200, '2023-01-01')
]
c.executemany('INSERT INTO communications VALUES (?,?,?,?,?)', comms)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
