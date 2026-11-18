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
c = conn.cursor()

# Create tables with slightly obfuscated names to force schema analysis
c.execute('''CREATE TABLE t_usr (id INTEGER PRIMARY KEY, nm TEXT, dept INTEGER, rl TEXT)''')
c.execute('''CREATE TABLE t_dpt (id INTEGER PRIMARY KEY, dnm TEXT)''')
c.execute('''CREATE TABLE t_ast (id INTEGER PRIMARY KEY, anm TEXT, owner_dept INTEGER, class TEXT)''')
c.execute('''CREATE TABLE t_prm (usr_id INTEGER, ast_id INTEGER, lvl TEXT)''')

# Insert Departments
c.executemany('INSERT INTO t_dpt VALUES (?,?)', [
    (10, 'HR'),
    (20, 'IT'),
    (30, 'Sales')
])

# Insert Users (id, name, dept, role)
c.executemany('INSERT INTO t_usr VALUES (?,?,?,?)', [
    (1, 'Alice', 10, 'STAFF'),
    (2, 'Bob', 20, 'STAFF'),
    (3, 'Charlie', 10, 'AUDITOR'),
    (4, 'Dave', 30, 'STAFF'),
    (5, 'Eve', 20, 'MANAGER')
])

# Insert Assets (id, name, owner_dept, class)
c.executemany('INSERT INTO t_ast VALUES (?,?,?,?)', [
    (100, 'HR_DB', 10, 'RESTRICTED'),
    (101, 'Public_Wiki', 20, 'PUBLIC'),
    (102, 'Sales_CRM', 30, 'RESTRICTED')
])

# Insert Permissions (usr_id, ast_id, lvl)
c.executemany('INSERT INTO t_prm VALUES (?,?,?)', [
    (1, 100, 'READ'),  # Valid: Alice in HR accesses HR DB
    (2, 100, 'WRITE'), # VIOLATION: Bob in IT accesses RESTRICTED HR DB
    (3, 102, 'READ'),  # Valid: Charlie accesses Sales CRM, but is AUDITOR
    (4, 101, 'READ'),  # Valid: Dave accesses Public Wiki (not RESTRICTED)
    (4, 100, 'READ'),  # VIOLATION: Dave in Sales accesses RESTRICTED HR DB
    (5, 102, 'READ')   # VIOLATION: Eve in IT accesses RESTRICTED Sales CRM
])

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
