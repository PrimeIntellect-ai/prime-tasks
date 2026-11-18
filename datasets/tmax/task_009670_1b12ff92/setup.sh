#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import sqlite3

db_path = '/home/user/compliance.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('CREATE TABLE employees (emp_id TEXT, assigned_node TEXT)')
cur.execute('CREATE TABLE network_edges (source TEXT, target TEXT)')
cur.execute('CREATE TABLE access_logs (log_id INTEGER, emp_id TEXT, accessed_node TEXT, timestamp TEXT)')

# Insert Employees
employees = [
    ('E001', 'NodeA'),
    ('E002', 'NodeD'),
    ('E003', 'NodeG')
]
cur.executemany('INSERT INTO employees VALUES (?, ?)', employees)

# Insert Edges
edges = [
    ('NodeA', 'NodeB'),
    ('NodeB', 'NodeC'),
    ('NodeC', 'NodeZ'), # NodeZ is 3 hops from NodeA
    ('NodeD', 'NodeE'),
    ('NodeE', 'NodeF'),
    ('NodeF', 'NodeA'),
    ('NodeG', 'NodeH')
]
cur.executemany('INSERT INTO network_edges VALUES (?, ?)', edges)

# Insert Access Logs
logs = [
    (1, 'E001', 'NodeA', '2023-10-01T10:00:00Z'), # Valid (0 hops)
    (2, 'E001', 'NodeB', '2023-10-01T10:05:00Z'), # Valid (1 hop)
    (3, 'E001', 'NodeC', '2023-10-01T10:10:00Z'), # Valid (2 hops)
    (4, 'E001', 'NodeZ', '2023-10-01T10:15:00Z'), # Violation (3 hops)
    (5, 'E002', 'NodeF', '2023-10-02T11:00:00Z'), # Valid (2 hops)
    (6, 'E002', 'NodeA', '2023-10-02T11:05:00Z'), # Violation (3 hops)
    (7, 'E002', 'NodeA', '2023-10-02T11:10:00Z'), # Violation (duplicate)
    (8, 'E003', 'NodeA', '2023-10-03T12:00:00Z'), # Violation (unreachable)
    (9, 'E003', 'NodeH', '2023-10-03T12:05:00Z')  # Valid (1 hop)
]
cur.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)

conn.commit()
conn.close()
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
