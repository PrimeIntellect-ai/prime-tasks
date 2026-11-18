#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('CREATE TABLE employees (emp_id INT, name TEXT, manager_id INT, dept_id INT)')
cur.execute('CREATE TABLE permissions (dept_id INT, resource TEXT)')

employees_data = [
    (1, 'Alice (CEO)', None, 10),
    (2, 'Bob (VP Engineering)', 1, 20),
    (3, 'Charlie (VP Sales)', 1, 30),
    (4, 'Dave (Senior Dev)', 2, 20),
    (5, 'Eve (Junior Dev)', 4, 20),
    (6, 'Frank (Sales Lead)', 3, 30),
    (7, 'Grace (Intern)', 5, 20)
]

permissions_data = [
    (10, 'All Systems'),
    (20, 'Code Repository'),
    (30, 'CRM Database')
]

cur.executemany('INSERT INTO employees VALUES (?, ?, ?, ?)', employees_data)
cur.executemany('INSERT INTO permissions VALUES (?, ?)', permissions_data)
conn.commit()
conn.close()

buggy_script = """import sqlite3
import json

conn = sqlite3.connect('/home/user/audit.db')
cur = conn.cursor()

# BUG: Implicit cross join, no recursion for path
cur.execute('''
    SELECT e.emp_id, e.name, p.resource, '1' as path
    FROM employees e, permissions p
''')
rows = cur.fetchall()

result = []
for r in rows:
    result.append({
        "emp_id": r[0],
        "name": r[1],
        "resource": r[2],
        "path": r[3]
    })

with open('/home/user/compliance_graph.json', 'w') as f:
    json.dump(result, f, indent=2)
"""

with open('/home/user/generate_report.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
