#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create tables
c.execute('CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department_id INTEGER, clearance_level INTEGER)')
c.execute('CREATE TABLE system_clearances (system_name TEXT PRIMARY KEY, required_clearance INTEGER)')
c.execute('CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, employee_id INTEGER, system_name TEXT, access_time TEXT)')

# Insert Departments
departments = [(1, 'Sales'), (2, 'HR'), (3, 'Engineering'), (4, 'Executive')]
c.executemany('INSERT INTO departments VALUES (?,?)', departments)

# Insert Employees
employees = [
    (101, 'Alice Smith', 1, 1),
    (102, 'Bob Jones', 2, 2),
    (103, 'Charlie Brown', 3, 3),
    (104, 'Diana Prince', 4, 5)
]
c.executemany('INSERT INTO employees VALUES (?,?,?,?)', employees)

# Insert System Clearances
systems = [
    ('Email', 1),
    ('Payroll', 2),
    ('SourceCode', 3),
    ('ProjectX', 3),
    ('Mainframe', 4),
    ('RootDB', 5)
]
c.executemany('INSERT INTO system_clearances VALUES (?,?)', systems)

# Insert Access Logs (Valid)
logs = [
    (1, 101, 'Email', '2023-10-01 08:00:00'),
    (2, 102, 'Payroll', '2023-10-01 09:00:00'),
    (3, 103, 'SourceCode', '2023-10-01 09:30:00'),
    (4, 104, 'RootDB', '2023-10-01 10:00:00')
]

# Insert Access Logs (Violations)
violations = [
    (5, 101, 'ProjectX', '2023-10-01 10:00:00'),
    (6, 102, 'Mainframe', '2023-10-02 11:30:00'),
    (7, 103, 'RootDB', '2023-10-03 09:15:00')
]
c.executemany('INSERT INTO access_logs VALUES (?,?,?,?)', logs + violations)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
