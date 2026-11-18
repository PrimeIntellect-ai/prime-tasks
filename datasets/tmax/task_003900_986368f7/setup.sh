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
cursor = conn.cursor()

cursor.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT)''')
cursor.execute('''CREATE TABLE access_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, resource TEXT, access_timestamp DATETIME)''')
cursor.execute('''CREATE TABLE auth_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, ip_address TEXT, auth_timestamp DATETIME)''')

employees = [
    (1, 'Alice Smith', 'Engineering'),
    (2, 'Bob Jones', 'Engineering'),
    (3, 'Charlie Brown', 'HR'),
    (4, 'Diana Prince', 'Engineering')
]
cursor.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

access = [
    (1, 1, '/etc/shadow', '2023-10-01 10:00:00'),
    (2, 2, '/etc/shadow', '2023-10-01 10:05:00'),
    (3, 3, '/etc/shadow', '2023-10-01 10:05:00'),
    (4, 4, '/etc/shadow', '2023-10-01 09:00:00'),
    (5, 1, '/etc/passwd', '2023-10-01 11:00:00'),
    (6, 2, '/etc/shadow', '2023-10-02 10:05:00')
]
cursor.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?)", access)

auth = [
    (1, 1, '192.168.1.10', '2023-10-01 09:50:00'),
    (2, 2, '192.168.1.11', '2023-10-01 10:01:00'),
    (3, 3, '192.168.1.12', '2023-10-01 10:01:00'),
    (4, 4, '192.168.2.10', '2023-10-01 08:50:00'),
    (5, 1, '10.0.0.5', '2023-10-01 10:50:00'),
    (6, 2, '192.168.1.15', '2023-10-02 10:01:00'),
    (7, 1, '192.168.1.100', '2023-10-01 10:10:00') 
]
cursor.executemany("INSERT INTO auth_logs VALUES (?, ?, ?, ?)", auth)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
