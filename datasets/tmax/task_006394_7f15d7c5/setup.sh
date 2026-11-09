#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

def setup_db():
    conn = sqlite3.connect('/home/user/corporate_data.db')
    cursor = conn.cursor()

    cursor.execute('''CREATE TABLE employees (emp_id TEXT PRIMARY KEY, name TEXT, manager_id TEXT)''')
    cursor.execute('''CREATE TABLE project_dependencies (project_id TEXT, depends_on_project_id TEXT)''')

    # Employee hierarchy
    employees = [
        ('E001', 'Alice', None),
        ('E002', 'Bob', 'E001'),
        ('E003', 'Charlie', 'E001'),
        ('E004', 'David', 'E002'),
        ('E005', 'Eve', 'E004'),
        ('E006', 'Frank', 'E008'),
        ('E007', 'Grace', 'E003')
    ]
    cursor.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

    # Project dependencies
    deps = [
        ('P500', 'P600'),
        ('P500', 'P700'),
        ('P999', 'P100'),
        ('P999', 'P200'),
        ('P999', 'P300'),
        ('P999', 'P400'),
        ('P999', 'P500')
    ]
    cursor.executemany("INSERT INTO project_dependencies VALUES (?, ?)", deps)

    conn.commit()
    conn.close()

if __name__ == '__main__':
    setup_db()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
