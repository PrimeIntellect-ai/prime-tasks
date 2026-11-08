#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('CREATE TABLE users (user_id TEXT, dept_id TEXT)')
c.execute('CREATE TABLE permissions (dept_id TEXT, resource_id TEXT)')
c.execute('CREATE TABLE access_logs (user_id TEXT, resource_id TEXT)')

users_data = [('u1', 'Sales'), ('u2', 'Sales'), ('u3', 'IT'), ('u4', 'HR')]
perms_data = [('Sales', 'r1'), ('Sales', 'r2'), ('IT', 'r1'), ('IT', 'r3'), ('HR', 'r4')]
access_data = [
    ('u1', 'r1'), # Authorized
    ('u1', 'r3'), # Unauthorized (Sales doesn't have r3)
    ('u2', 'r2'), # Authorized
    ('u3', 'r4'), # Unauthorized (IT doesn't have r4)
    ('u3', 'r2'), # Unauthorized (IT doesn't have r2)
    ('u4', 'r4')  # Authorized
]

c.executemany('INSERT INTO users VALUES (?, ?)', users_data)
c.executemany('INSERT INTO permissions VALUES (?, ?)', perms_data)
c.executemany('INSERT INTO access_logs VALUES (?, ?)', access_data)

conn.commit()
conn.close()
EOF
    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    cat << 'EOF' > /home/user/generate_report.py
import sqlite3
import csv
import json

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

# BROKEN QUERY WITH IMPLICIT CROSS JOIN
query = """
SELECT a.user_id, a.resource_id, u.dept_id
FROM access_logs a, users u, permissions p
WHERE a.user_id = u.user_id 
  AND p.resource_id != a.resource_id
"""

c.execute(query)
results = c.fetchall()

# TODO: Export unauthorized_edges.csv
# TODO: Export dept_summary.json

conn.close()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
