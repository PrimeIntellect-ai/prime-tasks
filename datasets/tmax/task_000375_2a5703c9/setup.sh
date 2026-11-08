#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, clearance_level INTEGER, termination_date TEXT)''')
c.execute('''CREATE TABLE systems (sys_id INTEGER PRIMARY KEY, sys_name TEXT, required_clearance INTEGER)''')
c.execute('''CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, sys_id INTEGER, access_timestamp TEXT)''')

employees = [
    (1, 'Alice', 5, None),
    (2, 'Bob', 2, None),
    (3, 'Charlie', 4, '2023-10-01'),
    (4, 'Diana', 1, '2023-09-15')
]
c.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", employees)

systems = [
    (101, 'HR_Portal', 2),
    (102, 'Financial_DB', 4),
    (103, 'Root_Servers', 5)
]
c.executemany("INSERT INTO systems VALUES (?, ?, ?)", systems)

access_logs = [
    # Valid accesses
    (1001, 1, 103, '2023-10-10 10:00:00'), # Alice valid
    (1002, 2, 101, '2023-10-11 11:00:00'), # Bob valid
    (1003, 3, 102, '2023-09-30 09:00:00'), # Charlie valid before term

    # Violations
    (1004, 2, 102, '2023-10-12 12:00:00'), # Bob CLEARANCE violation (level 2 < 4)
    (1005, 3, 101, '2023-10-05 14:00:00'), # Charlie TERMINATED violation (access > term date)
    (1006, 4, 103, '2023-09-20 08:00:00')  # Diana BOTH -> should be TERMINATED
]
c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?)", access_logs)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
