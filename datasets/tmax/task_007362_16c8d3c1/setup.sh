#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = '/home/user/employees.db'
jsonl_path = '/home/user/access_logs.jsonl'

# Clean up if exists
if os.path.exists(db_path): os.remove(db_path)
if os.path.exists(jsonl_path): os.remove(jsonl_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, role TEXT)')
c.execute('CREATE TABLE permissions (role TEXT, resource TEXT)')

users = [
    (1, 'Alice', 'Admin'), 
    (2, 'Bob', 'Engineer'), 
    (3, 'Charlie', 'Intern'),
    (4, 'Diana', 'Manager')
]
c.executemany('INSERT INTO users VALUES (?,?,?)', users)

perms = [
    ('Admin', 'Payroll'), 
    ('Admin', 'Codebase'), 
    ('Admin', 'PublicDocs'),
    ('Engineer', 'Codebase'), 
    ('Engineer', 'PublicDocs'),
    ('Intern', 'PublicDocs'),
    ('Manager', 'Payroll'),
    ('Manager', 'PublicDocs')
]
c.executemany('INSERT INTO permissions VALUES (?,?)', perms)
conn.commit()
conn.close()

logs = [
    {"timestamp": "2023-10-01T08:00:00Z", "user_id": 1, "resource": "Payroll"},
    {"timestamp": "2023-10-01T08:05:00Z", "user_id": 2, "resource": "Payroll"},
    {"timestamp": "2023-10-01T08:10:00Z", "user_id": 3, "resource": "Codebase"},
    {"timestamp": "2023-10-01T08:15:00Z", "user_id": 2, "resource": "Codebase"},
    {"timestamp": "2023-10-01T08:20:00Z", "user_id": 4, "resource": "Codebase"},
    {"timestamp": "2023-10-01T08:25:00Z", "user_id": 3, "resource": "PublicDocs"}
]

with open(jsonl_path, 'w') as f:
    for l in logs:
        f.write(json.dumps(l) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
