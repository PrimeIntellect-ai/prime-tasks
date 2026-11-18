#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
from datetime import datetime, timedelta

db_path = "/home/user/rbac.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, created_at DATETIME)")
cursor.execute("CREATE TABLE roles (id INTEGER PRIMARY KEY, role_name TEXT)")
cursor.execute("CREATE TABLE role_hierarchy (parent_role_id INTEGER, child_role_id INTEGER)")
cursor.execute("CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER)")
cursor.execute("CREATE TABLE role_permissions (role_id INTEGER, resource_name TEXT)")

# Insert roles
roles = [
    (1, 'super_admin'),
    (2, 'finance_admin'),
    (3, 'payment_admin'),
    (4, 'guest'),
    (5, 'it_support')
]
cursor.executemany("INSERT INTO roles VALUES (?, ?)", roles)

# Insert hierarchy
hierarchy = [
    (1, 2),
    (2, 3),
    (1, 5)
]
cursor.executemany("INSERT INTO role_hierarchy VALUES (?, ?)", hierarchy)

# Insert permissions
permissions = [
    (3, 'SWIFT_PAYMENT_GATEWAY'),
    (5, 'PRINTER_ACCESS')
]
cursor.executemany("INSERT INTO role_permissions VALUES (?, ?)", permissions)

# Insert users
now = datetime(2023, 1, 1)
users = [
    (1, 'alice', now - timedelta(days=10)),
    (2, 'bob', now - timedelta(days=5)),
    (3, 'charlie', now - timedelta(days=2)),
    (4, 'david', now - timedelta(days=1)),
    (5, 'eve', now - timedelta(days=8))
]
cursor.executemany("INSERT INTO users VALUES (?, ?, ?)", users)

# Assign users to roles
user_roles = [
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 1)
]
cursor.executemany("INSERT INTO user_roles VALUES (?, ?)", user_roles)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
