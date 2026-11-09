#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/data.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)")
cursor.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER, salary INTEGER)")
cursor.execute("CREATE INDEX idx_manager ON employees(manager_id)")

departments = [
    (1, "Executive"),
    (2, "Operations"),
    (3, "Engineering"),
    (4, "QA")
]
cursor.executemany("INSERT INTO departments VALUES (?, ?)", departments)

employees = [
    (1, "Alice CEO", None, 1, 500000),
    (10, "Bob VP", 1, 2, 250000),
    (42, "Charlie Director", 10, 3, 180000),
    (404, "Diana Manager", 42, 3, 140000),
    (845, "Eve Engineer", 404, 3, 110000),
    (999, "Frank QA", 404, 4, 90000)
]
cursor.executemany("INSERT INTO employees VALUES (?, ?, ?, ?, ?)", employees)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
