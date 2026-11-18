#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/audit.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE employees (id INTEGER, name TEXT)")
c.execute("CREATE TABLE systems (id INTEGER, name TEXT, sensitivity TEXT)")
c.execute("CREATE TABLE employee_roles (emp_id INTEGER, role_id INTEGER)")
c.execute("CREATE TABLE role_access (role_id INTEGER, system_id INTEGER)")
c.execute("CREATE TABLE system_connections (source_id INTEGER, target_id INTEGER)")

# Populate Data
c.executemany("INSERT INTO employees VALUES (?, ?)", [
    (1, "Alice"),
    (2, "Bob"),
    (3, "Eve")
])

c.executemany("INSERT INTO systems VALUES (?, ?, ?)", [
    (101, "HR_Portal", "Low"),
    (102, "Dev_Server", "Medium"),
    (103, "Prod_App_Server", "High"),
    (104, "Main_Ledger", "Critical"),
    (105, "Backup_Server", "High")
])

# Roles: 10: Intern, 20: Dev, 30: Admin
c.executemany("INSERT INTO employee_roles VALUES (?, ?)", [
    (1, 30), # Alice is Admin
    (2, 20), # Bob is Dev
    (3, 10)  # Eve is Intern
])

# Role Access
c.executemany("INSERT INTO role_access VALUES (?, ?)", [
    (30, 104), # Admin -> Main_Ledger
    (30, 103), # Admin -> Prod_App_Server
    (20, 102), # Dev -> Dev_Server
    (10, 101), # Intern -> HR_Portal
    (10, 102)  # Intern -> Dev_Server
])

# System Connections (The Attack Path)
c.executemany("INSERT INTO system_connections VALUES (?, ?)", [
    (101, 105), # HR_Portal -> Backup_Server
    (102, 103), # Dev_Server -> Prod_App_Server
    (103, 104), # Prod_App_Server -> Main_Ledger
    (105, 102)  # Backup_Server -> Dev_Server
])

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
