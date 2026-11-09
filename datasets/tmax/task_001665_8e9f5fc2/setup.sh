#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
import os

db_path = '/home/user/company.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER
)
''')

random.seed(42)
employees = [(1, "CEO", None)]
for i in range(2, 10001):
    manager = random.randint(1, i - 1)
    if i == 42:
        manager = 5
    employees.append((i, f"Employee_{i}", manager))

cursor.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
