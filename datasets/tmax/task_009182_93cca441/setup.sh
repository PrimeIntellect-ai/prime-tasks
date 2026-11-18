#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Create tables
cur.executescript("""
    CREATE TABLE departments (
        dept_id INTEGER PRIMARY KEY,
        name TEXT,
        parent_dept_id INTEGER
    );
    CREATE TABLE employees (
        emp_id INTEGER PRIMARY KEY,
        name TEXT,
        dept_id INTEGER
    );
    CREATE TABLE access_logs (
        log_id INTEGER PRIMARY KEY,
        emp_id INTEGER,
        access_time TEXT,
        resource TEXT
    );
""")

# Insert Data
cur.executescript("""
    INSERT INTO departments VALUES (1, 'Finance', NULL);
    INSERT INTO departments VALUES (2, 'Payroll', 1);
    INSERT INTO departments VALUES (3, 'Accounts Payable', 2);
    INSERT INTO departments VALUES (4, 'IT', NULL);
    INSERT INTO departments VALUES (5, 'HR', NULL);

    INSERT INTO employees VALUES (101, 'Alice', 1);
    INSERT INTO employees VALUES (102, 'Bob', 2);
    INSERT INTO employees VALUES (103, 'Charlie', 3);
    INSERT INTO employees VALUES (104, 'David', 4);

    INSERT INTO access_logs VALUES (1001, 101, '2023-10-01 09:00:00', 'ServerA');
    INSERT INTO access_logs VALUES (1002, 102, '2023-10-01 09:15:00', 'ServerB');
    INSERT INTO access_logs VALUES (1003, 103, '2023-10-01 09:30:00', 'ServerC');
    INSERT INTO access_logs VALUES (1004, 104, '2023-10-01 09:45:00', 'ServerD');
    INSERT INTO access_logs VALUES (1005, 101, '2023-10-01 10:00:00', 'ServerA');
""")
conn.commit()
conn.close()

# Create the broken python script
broken_script = """import sqlite3
import csv

conn = sqlite3.connect('/home/user/audit.db')
cur = conn.cursor()

# BAD QUERY: Implicit cross join and no recursion
query = '''
SELECT e.name, d.name, a.access_time, a.resource
FROM employees e, departments d, access_logs a
WHERE d.name = 'Finance'
'''

cur.execute(query)
rows = cur.fetchall()

with open('/home/user/audit_results.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['EmployeeName', 'DepartmentName', 'AccessTime', 'Resource'])
    writer.writerows(rows)

conn.close()
"""
with open('/home/user/audit.py', 'w') as f:
    f.write(broken_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
