#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import os

db_path = "/home/user/company.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE t_992_depts (
    dept_id INTEGER PRIMARY KEY,
    dept_name TEXT NOT NULL
)
''')

cursor.execute('''
CREATE TABLE t_881_emps (
    emp_id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    manager_id INTEGER,
    department_id INTEGER,
    FOREIGN KEY(manager_id) REFERENCES t_881_emps(emp_id),
    FOREIGN KEY(department_id) REFERENCES t_992_depts(dept_id)
)
''')

cursor.executemany('INSERT INTO t_992_depts (dept_id, dept_name) VALUES (?, ?)', [
    (1, 'Executive'),
    (2, 'Engineering'),
    (3, 'Sales')
])

emps = [
    (1, 'Alice', None, 1),
    (2, 'Bob', 1, 2),
    (3, 'Heidi', 1, 3),
    (4, 'Charlie', 2, 2),
    (5, 'Frank', 2, 2),
    (6, 'Dave', 4, 2),
    (7, 'Eve', 4, 2),
    (8, 'Grace', 5, 2),
    (9, 'Ivan', 3, 3),
    (10, 'Judy', 4, 2)
]

cursor.executemany('INSERT INTO t_881_emps VALUES (?, ?, ?, ?)', emps)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
