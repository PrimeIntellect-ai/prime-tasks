#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/compliance.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE departments (dept_id INTEGER PRIMARY KEY, dept_name TEXT)")
c.execute("CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER)")
c.execute("CREATE TABLE restricted_assets (asset_id INTEGER PRIMARY KEY, asset_name TEXT, owning_dept_id INTEGER)")
c.execute("CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, asset_id INTEGER, access_time DATETIME)")

# Insert Departments
departments = [(1, 'Engineering'), (2, 'Finance'), (3, 'HR')]
c.executemany("INSERT INTO departments VALUES (?, ?)", departments)

# Insert Employees
employees = [
    (101, 'Alice', 1),
    (102, 'Bob', 1),
    (103, 'Charlie', 2),
    (104, 'Diana', 3)
]
c.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

# Insert Assets
assets = [
    (1001, 'Source Code Repo', 1),
    (1002, 'Payroll DB', 2),
    (1003, 'Employee Records', 3),
    (1004, 'Q1 Financials', 2)
]
c.executemany("INSERT INTO restricted_assets VALUES (?, ?, ?)", assets)

# Insert Access Logs
logs = [
    (1, 101, 1001, '2023-10-01 10:00:00'), # Alice (Eng) accesses Eng asset (OK)
    (2, 102, 1002, '2023-10-02 11:30:00'), # Bob (Eng) accesses Finance asset (Anomaly)
    (3, 103, 1004, '2023-10-05 09:15:00'), # Charlie (Fin) accesses Fin asset (OK)
    (4, 101, 1003, '2023-10-15 14:20:00'), # Alice (Eng) accesses HR asset (Anomaly)
    (5, 102, 1002, '2023-11-01 08:00:00'), # Bob (Eng) accesses Finance asset (Outside date range)
]
c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?)", logs)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
