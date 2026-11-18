#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/company.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE employees (emp_id TEXT PRIMARY KEY, name TEXT, manager_id TEXT)")

data = [
    ("E1", "Alice (CEO)", None),
    ("E2", "Bob (VP)", "E1"),
    ("E3", "Charlie (VP)", "E1"),
    ("E4", "Diana (Director)", "E2"),
    ("E5", "Evan (Manager)", "E4"),
    ("E6", "Fiona (Staff)", "E5"),
    ("E7", "George (Staff)", "E3")
]

c.executemany("INSERT INTO employees VALUES (?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
