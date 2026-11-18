#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import sqlite3

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE roles (role_id INTEGER PRIMARY KEY, role_name TEXT)''')
c.execute('''CREATE TABLE role_hierarchy (role_id INTEGER, inherits_role_id INTEGER)''')
c.execute('''CREATE TABLE employee_roles (emp_id INTEGER, role_id INTEGER)''')

# Insert employees
employees = [
    (101, 'Alice'),
    (102, 'Bob'),
    (103, 'Charlie'),
    (104, 'Dave'),
    (105, 'Eve'),
    (106, 'Frank')
]
c.executemany('INSERT INTO employees VALUES (?, ?)', employees)

# Insert roles
roles = [
    (1, 'SuperAdmin'),
    (2, 'SystemAdmin'),
    (3, 'DBAdmin'),
    (4, 'Developer'),
    (5, 'Intern'),
    (6, 'Manager')
]
c.executemany('INSERT INTO roles VALUES (?, ?)', roles)

# Insert hierarchy:
hierarchy = [
    (2, 1),
    (3, 2),
    (6, 1),
    (4, 3)
]
c.executemany('INSERT INTO role_hierarchy VALUES (?, ?)', hierarchy)

# Insert employee_roles
emp_roles = [
    (101, 1),
    (102, 5),
    (103, 2),
    (104, 4),
    (105, 5),
    (106, 6)
]
c.executemany('INSERT INTO employee_roles VALUES (?, ?)', emp_roles)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py

    cat << 'EOF' > /home/user/audit_report.py
import sqlite3
import json

def generate_report():
    conn = sqlite3.connect('/home/user/audit.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # BAD QUERY: Implicit cross join causing incorrect results
    bad_query = """
    SELECT DISTINCT e.id as emp_id, e.name 
    FROM employees e, employee_roles er, roles r, role_hierarchy rh
    WHERE r.role_name = 'SuperAdmin'
    """

    c.execute(bad_query)
    results = [dict(row) for row in c.fetchall()]

    with open('/home/user/admin_audit.json', 'w') as f:
        json.dump(results, f, indent=2)

if __name__ == '__main__':
    generate_report()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
