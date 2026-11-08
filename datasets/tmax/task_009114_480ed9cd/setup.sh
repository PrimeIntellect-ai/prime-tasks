#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

db_path = '/home/user/audit.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, emp_name TEXT)')
c.execute('CREATE TABLE records (record_id INTEGER PRIMARY KEY, sensitivity_level TEXT)')
c.execute('CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, record_id INTEGER, access_time DATETIME)')

# Insert employees
employees = [(1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana'), (5, 'Eve')]
c.executemany('INSERT INTO employees VALUES (?, ?)', employees)

# Insert records
records = [(101, 'LOW'), (102, 'MEDIUM'), (103, 'CRITICAL'), (104, 'CRITICAL')]
c.executemany('INSERT INTO records VALUES (?, ?)', records)

# Insert access logs
logs = [
    # Alice (emp 1) - 3 critical outside hours -> FLAGGED
    (1, 1, 103, '2023-10-01 19:30:00'),
    (2, 1, 104, '2023-10-02 07:15:00'),
    (3, 1, 103, '2023-10-03 22:00:00'),
    # Bob (emp 2) - 2 critical outside hours -> NOT FLAGGED (needs > 2)
    (4, 2, 103, '2023-10-01 06:00:00'),
    (5, 2, 104, '2023-10-02 23:00:00'),
    (6, 2, 103, '2023-10-03 12:00:00'), # During hours
    # Charlie (emp 3) - 4 critical outside hours -> FLAGGED
    (7, 3, 103, '2023-10-01 01:00:00'),
    (8, 3, 104, '2023-10-01 02:00:00'),
    (9, 3, 103, '2023-10-01 03:00:00'),
    (10, 3, 104, '2023-10-01 04:00:00'),
    # Diana (emp 4) - 5 non-critical outside hours -> NOT FLAGGED
    (11, 4, 101, '2023-10-01 20:00:00'),
    (12, 4, 102, '2023-10-02 21:00:00'),
    (13, 4, 101, '2023-10-03 22:00:00'),
    (14, 4, 102, '2023-10-04 23:00:00'),
    # Eve (emp 5) - 3 critical outside hours -> FLAGGED
    (15, 5, 103, '2023-10-01 18:01:00'),
    (16, 5, 104, '2023-10-02 07:59:00'),
    (17, 5, 103, '2023-10-03 19:00:00'),
]
c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
