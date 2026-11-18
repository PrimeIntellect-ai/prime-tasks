#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/company.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER
)
''')

# Insert data
# Depth 0
c.execute("INSERT INTO employees VALUES (1, 'Zack (CEO)', NULL)")

# Depth 1
c.execute("INSERT INTO employees VALUES (2, 'Yolanda', 1)")
c.execute("INSERT INTO employees VALUES (3, 'Xavier', 1)")

# Depth 2
c.execute("INSERT INTO employees VALUES (4, 'Wendy', 2)")
c.execute("INSERT INTO employees VALUES (5, 'Victor', 2)")
c.execute("INSERT INTO employees VALUES (6, 'Uma', 3)")
c.execute("INSERT INTO employees VALUES (7, 'Tom', 3)")

# Depth 3
c.execute("INSERT INTO employees VALUES (8, 'Sarah', 4)")
c.execute("INSERT INTO employees VALUES (9, 'Rachel', 5)")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
