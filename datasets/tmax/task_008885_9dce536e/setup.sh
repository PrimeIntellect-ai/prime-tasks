#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = '/home/user/company.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER)''')
c.execute('''CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE employee_projects (emp_id INTEGER, proj_id INTEGER)''')

# Populate data
departments = [(101, 'Engineering'), (102, 'Sales'), (103, 'Marketing')]
c.executemany('INSERT INTO departments VALUES (?,?)', departments)

employees = [(i, f'Emp_{i}', random.choice([101, 102, 103])) for i in range(1, 51)]
c.executemany('INSERT INTO employees VALUES (?,?,?)', employees)

projects = [(200 + i, f'Proj_{i}') for i in range(1, 11)]
c.executemany('INSERT INTO projects VALUES (?,?)', projects)

# Explicitly create some known cross-department collaborations
c.execute('UPDATE employees SET dept_id = 101 WHERE id = 1')
c.execute('UPDATE employees SET dept_id = 102 WHERE id = 2')
c.execute('UPDATE employees SET dept_id = 102 WHERE id = 3')
c.execute('UPDATE employees SET dept_id = 103 WHERE id = 4')

employee_projects = [
    (1, 201), (2, 201), 
    (3, 205), (4, 205)
]

# Add some random noise
random.seed(42)
for _ in range(100):
    employee_projects.append((random.randint(5, 50), random.randint(201, 210)))

c.executemany('INSERT INTO employee_projects VALUES (?,?)', employee_projects)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
