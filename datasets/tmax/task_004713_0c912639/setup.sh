#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/expenses.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, role TEXT, department_id INTEGER)')
c.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY, emp_id INTEGER, cat_id INTEGER, amount REAL, date TEXT)')

c.executemany('INSERT INTO departments VALUES (?, ?)', [
    (1, 'Sales'),
    (2, 'Engineering'),
    (3, 'HR')
])

c.executemany('INSERT INTO categories VALUES (?, ?)', [
    (1, 'Travel'),
    (2, 'Meals'),
    (3, 'Office Supplies')
])

c.executemany('INSERT INTO employees VALUES (?, ?, ?, ?)', [
    (1, 'Alice', 'Manager', 1),
    (2, 'Bob', 'Rep', 1),
    (3, 'Charlie', 'Dev', 2),
    (4, 'Diana', 'Recruiter', 3)
])

c.executemany('INSERT INTO expenses VALUES (?, ?, ?, ?, ?)', [
    (1, 1, 1, 1000.0, '2023-10-01'),
    (2, 2, 1, 2000.0, '2023-10-02'),
    (3, 3, 1, 500.0,  '2023-10-03'),
    (4, 1, 2, 100.0,  '2023-10-04'),
    (5, 2, 2, 50.0,   '2023-10-05'),
    (6, 4, 3, 200.0,  '2023-10-06'),
    (7, 3, 2, 120.0,  '2023-10-07'),
    (8, 2, 1, 1200.0, '2023-10-08')
])

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
