#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/company.db')
c = conn.cursor()

c.execute('''CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)''')
c.execute('''CREATE TABLE projects (project_id INTEGER PRIMARY KEY, project_name TEXT)''')
c.execute('''CREATE TABLE timesheets (emp_id INTEGER, project_id INTEGER, hours INTEGER)''')

# Insert Employees
employees = [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'Dave', 2),
    (5, 'Eve', 2),
    (6, 'Frank', 3)
]
c.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

# Insert Projects
projects = [
    (101, 'Alpha'),
    (102, 'Beta')
]
c.executemany("INSERT INTO projects VALUES (?, ?)", projects)

# Insert Timesheets
timesheets = [
    (1, 101, 10),
    (2, 101, 20),
    (2, 102, 5),
    (3, 102, 15),
    (4, 101, 10),
    (5, 102, 10),
    (6, 101, 5),
    (6, 102, 5)
]
c.executemany("INSERT INTO timesheets VALUES (?, ?, ?)", timesheets)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py

    chmod -R 777 /home/user
