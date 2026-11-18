#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/audit.db'

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''
CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER
)
''')

cursor.execute('''
CREATE TABLE access_logs (
    log_id INTEGER PRIMARY KEY,
    emp_id INTEGER,
    system_name TEXT,
    access_date DATE
)
''')

# Insert data
employees_data = [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'David', 2),
    (5, 'Eve', 2),
    (6, 'Frank', 3)
]
cursor.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees_data)

logs_data = [
    (1, 2, 'Vault', '2023-10-01'),
    (2, 2, 'Vault', '2023-10-02'),
    (3, 2, 'Vault', '2023-10-03'),
    (4, 2, 'Email', '2023-10-01'),
    (5, 3, 'Email', '2023-10-01'),
    (6, 3, 'Email', '2023-10-02'),
    (7, 4, 'Servers', '2023-10-01'),
    (8, 4, 'Servers', '2023-10-02'),
    (9, 4, 'Billing', '2023-10-03'),
    (10, 4, 'Billing', '2023-10-04'),
    (11, 5, 'HR_System', '2023-10-01')
]
cursor.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
