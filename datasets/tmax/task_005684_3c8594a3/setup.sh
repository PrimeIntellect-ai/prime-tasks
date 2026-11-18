#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import os

db_path = '/home/user/compliance_audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Create tables
cur.execute('''CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT)''')
cur.execute('''CREATE TABLE communications (msg_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp TEXT)''')
cur.execute('''CREATE TABLE systems (sys_id INTEGER PRIMARY KEY, sys_name TEXT, sensitivity TEXT)''')
cur.execute('''CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, sys_id INTEGER, access_time TEXT)''')

# Insert employees
employees = [
    (1, 'Alice Central'),
    (2, 'Bob Broker'),
    (3, 'Charlie Clerk'),
    (4, 'Diana Director'),
    (5, 'Evan Employee')
]
cur.executemany('INSERT INTO employees VALUES (?, ?)', employees)

# Insert communications
comms = [
    (1, 2, 1, '2023-01-01'),
    (2, 3, 1, '2023-01-02'),
    (3, 4, 1, '2023-01-03'),
    (4, 5, 1, '2023-01-04'),
    (5, 1, 2, '2023-01-05'),
    (6, 3, 2, '2023-01-06'),
    (7, 4, 2, '2023-01-07'),
    (8, 5, 3, '2023-01-08')
]
cur.executemany('INSERT INTO communications VALUES (?, ?, ?, ?)', comms)

# Insert systems
systems = [
    (101, 'Trading_Engine', 'High'),
    (102, 'HR_Portal', 'Low'),
    (103, 'Vault_DB', 'High'),
    (104, 'Cafeteria_Menu', 'Low')
]
cur.executemany('INSERT INTO systems VALUES (?, ?, ?)', systems)

# Insert access logs
logs = [
    (1, 1, 101, '2023-10-01 10:00:00'),
    (2, 1, 102, '2023-10-02 11:00:00'),
    (3, 1, 103, '2023-10-03 09:00:00'),
    (4, 2, 101, '2023-10-01 08:00:00'),
    (5, 3, 103, '2023-09-01 08:00:00'),
    (6, 3, 101, '2023-09-15 08:00:00')
]
cur.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
