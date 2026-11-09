#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the policies.json file
    cat << 'EOF' > policies.json
{
  "DOC-12A": {
    "allowed_groups": ["All-Staff"]
  },
  "DOC-77X": {
    "allowed_groups": ["Compliance", "IT-Admin"]
  }
}
EOF

    # Create the SQLite database setup script
    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('iam.db')
cursor = conn.cursor()

cursor.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT)')
cursor.execute('CREATE TABLE groups (id INTEGER PRIMARY KEY, group_name TEXT)')
cursor.execute('CREATE TABLE group_members (group_id INTEGER, member_user_id INTEGER, member_group_id INTEGER)')

users = [
    (1, 'alice'),
    (2, 'bob'),
    (3, 'charlie'),
    (4, 'david'),
    (5, 'eve')
]
cursor.executemany('INSERT INTO users VALUES (?, ?)', users)

groups = [
    (101, 'Compliance'),
    (102, 'IT-Admin'),
    (103, 'SysOps'),
    (104, 'All-Staff'),
    (105, 'Contractors')
]
cursor.executemany('INSERT INTO groups VALUES (?, ?)', groups)

memberships = [
    (101, 1, None),      # alice is in Compliance
    (102, 2, None),      # bob is in IT-Admin
    (102, None, 103),    # SysOps group is in IT-Admin (nested)
    (103, 3, None),      # charlie is in SysOps
    (104, 4, None),      # david is in All-Staff
    (104, None, 101),    # Compliance is in All-Staff
    (104, None, 102)     # IT-Admin is in All-Staff
]
cursor.executemany('INSERT INTO group_members VALUES (?, ?, ?)', memberships)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
