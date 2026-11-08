#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/compliance.db')
c = conn.cursor()

c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
c.execute("CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE user_groups (user_id INTEGER, group_id INTEGER)")
c.execute("CREATE TABLE group_trusts (group_id INTEGER, trusted_group_id INTEGER)")
c.execute("CREATE TABLE assets (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE group_assets (group_id INTEGER, asset_id INTEGER)")

# Insert users
users = [
    (1, 'Mallory', 'Engineering'),
    (2, 'Alice', 'Compliance'),
    (3, 'Bob', 'Compliance')
]
c.executemany("INSERT INTO users VALUES (?, ?, ?)", users)

# Insert groups
groups = [
    (10, 'Intern_Group'),
    (20, 'Staff_Group'),
    (30, 'Admin_Group'),
    (40, 'Compliance_Viewers')
]
c.executemany("INSERT INTO groups VALUES (?, ?)", groups)

# Insert assets
assets = [
    (100, 'Mainframe'),
    (200, 'Audit_Logs'),
    (300, 'Source_Code')
]
c.executemany("INSERT INTO assets VALUES (?, ?)", assets)

# User to Group
user_groups = [
    (1, 10), # Mallory in Intern_Group
    (2, 40), # Alice in Compliance_Viewers
    (3, 40)  # Bob in Compliance_Viewers
]
c.executemany("INSERT INTO user_groups VALUES (?, ?)", user_groups)

# Group Trusts
group_trusts = [
    (10, 20), # Intern_Group inherits from Staff_Group
    (20, 30)  # Staff_Group inherits from Admin_Group
]
c.executemany("INSERT INTO group_trusts VALUES (?, ?)", group_trusts)

# Group to Asset
group_assets = [
    (30, 100), # Admin_Group has access to Mainframe
    (40, 200), # Compliance_Viewers access Audit_Logs
    (20, 300)  # Staff_Group access Source_Code
]
c.executemany("INSERT INTO group_assets VALUES (?, ?)", group_assets)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    cat << 'EOF' > /home/user/bad_query.sql
SELECT u.name AS user_name, a.name AS asset_name 
FROM users u, user_groups ug, groups g, group_assets ga, assets a 
WHERE u.department = 'Compliance' 
  AND u.id = ug.user_id 
  AND g.id = ga.group_id 
  AND ga.asset_id = a.id;
EOF

    chmod -R 777 /home/user
