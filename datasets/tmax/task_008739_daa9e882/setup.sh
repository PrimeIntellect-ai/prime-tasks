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

c.execute('''CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE certifications (cert_id INTEGER PRIMARY KEY, emp_id INTEGER, system_name TEXT, expiration_date TEXT)''')
c.execute('''CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, system_name TEXT, access_time TEXT, status TEXT)''')

# Insert Employees
c.executemany("INSERT INTO employees VALUES (?, ?)", [
    (101, 'Alice'),
    (102, 'Bob'),
    (103, 'Charlie')
])

# Insert Certifications
c.executemany("INSERT INTO certifications VALUES (?, ?, ?, ?)", [
    (1, 101, 'FINANCE', '2023-12-31'),
    (2, 103, 'IT', '2025-01-01')
])

# Insert Access Logs
c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", [
    (1001, 101, 'FINANCE', '2023-10-01', 'GRANTED'), # Valid
    (1002, 101, 'FINANCE', '2024-01-05', 'GRANTED'), # Violation: Expired
    (1003, 102, 'HR', '2023-11-01', 'GRANTED'),      # Violation: No cert
    (1004, 103, 'IT', '2023-05-05', 'GRANTED'),      # Valid
    (1005, 103, 'IT', '2026-06-01', 'DENIED')        # Valid: Denied (even though expired)
])

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
