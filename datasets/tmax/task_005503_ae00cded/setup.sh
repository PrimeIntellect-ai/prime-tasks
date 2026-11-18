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

c.execute('CREATE TABLE emp (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE sys (id INTEGER PRIMARY KEY, hostname TEXT)')
c.execute('CREATE TABLE log (log_id INTEGER PRIMARY KEY, e_id INTEGER, s_id INTEGER, ts DATETIME)')

# Insert Employees
emps = [(101, 'Alice'), (102, 'Bob'), (103, 'Charlie'), (104, 'Diana')]
c.executemany('INSERT INTO emp VALUES (?, ?)', emps)

# Insert Systems
syss = [(10, 'DB1'), (20, 'Web1'), (30, 'App1'), (40, 'AuthServer')]
c.executemany('INSERT INTO sys VALUES (?, ?)', syss)

# Insert Logs
logs = [
    (1, 101, 10, '2023-01-01 10:00:00'),
    (2, 101, 20, '2023-01-01 10:05:00'),
    (3, 101, 30, '2023-01-01 10:10:00'),
    (4, 101, 40, '2023-01-01 10:15:00'),
    (5, 102, 40, '2023-01-01 11:00:00'),
    (6, 103, 30, '2023-01-01 12:00:00'),
    (7, 103, 40, '2023-01-01 12:05:00'),
    (8, 104, 10, '2023-01-01 13:00:00'),
    (9, 104, 40, '2023-01-01 13:05:00')
]
c.executemany('INSERT INTO log VALUES (?, ?, ?, ?)', logs)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
