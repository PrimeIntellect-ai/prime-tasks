#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
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

c.execute("CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT)")
c.execute("CREATE TABLE systems (sys_id INTEGER PRIMARY KEY, sys_name TEXT, sensitivity_level INTEGER)")
c.execute("CREATE TABLE direct_access (emp_id INTEGER, sys_id INTEGER)")

employees = [
    (1, 'CEO', None, 'Executive'),
    (2, 'VP Trading', 1, 'Trading'),
    (3, 'VP Audit', 1, 'Audit'),
    (4, 'Trader A', 2, 'Trading'),
    (5, 'Auditor A', 3, 'Audit'),
    (6, 'Rogue Ops', 1, 'SpecialOps'),
    (7, 'IT Manager', 1, 'IT'),
    (8, 'IT Guy 1', 7, 'IT'),
    (9, 'IT Guy 2', 7, 'IT'),
    (10, 'Intern', 8, 'IT')
]
c.executemany("INSERT INTO employees VALUES (?,?,?,?)", employees)

systems = [
    (101, 'Trading Platform', 5),
    (202, 'Audit Platform', 5),
    (303, 'Email', 1)
]
c.executemany("INSERT INTO systems VALUES (?,?,?)", systems)

access = [
    (4, 101),
    (5, 202),
    (6, 101),
    (6, 202),
    (8, 101),
    (10, 202)
]
c.executemany("INSERT INTO direct_access VALUES (?,?)", access)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
