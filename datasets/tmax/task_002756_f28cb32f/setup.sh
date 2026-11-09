#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE access_events (
    event_id INTEGER PRIMARY KEY,
    employee_id TEXT,
    resource_id TEXT,
    action TEXT,
    timestamp INTEGER
)''')

c.execute('''CREATE TABLE resource_hierarchy (
    parent_resource TEXT,
    child_resource TEXT
)''')

# Build hierarchy
hierarchy = [
    ('Super_Role', 'Admin_Role'),
    ('Super_Role', 'Audit_Role'),
    ('Admin_Role', 'Vault_Role'),
    ('Vault_Role', 'Vault_Open'),
    ('Audit_Role', 'Vault_Close'),
    ('IT_Support', 'Vault_Open')
]
c.executemany('INSERT INTO resource_hierarchy VALUES (?, ?)', hierarchy)

# Build events
events = [
    # E001: Direct violation (Granted both, never revoked)
    (1, 'E001', 'Vault_Open', 'GRANT', 100),
    (2, 'E001', 'Vault_Close', 'GRANT', 110),

    # E002: Inherited violation (Gets Super_Role which maps to both)
    (3, 'E002', 'Super_Role', 'GRANT', 120),

    # E003: Revoked violation (Granted both, but Vault_Close was revoked) -> NOT a violator
    (4, 'E003', 'Admin_Role', 'GRANT', 130), # Gets Vault_Open
    (5, 'E003', 'Vault_Close', 'GRANT', 140),
    (6, 'E003', 'Vault_Close', 'REVOKE', 150), # Revoked later!

    # E004: Stale row check (Revoked earlier, granted later) -> IS a violator
    (7, 'E004', 'Vault_Open', 'REVOKE', 160),
    (8, 'E004', 'Vault_Open', 'GRANT', 170),
    (9, 'E004', 'Vault_Close', 'GRANT', 180),

    # E005: Safe user (Only has one)
    (10, 'E005', 'IT_Support', 'GRANT', 190)
]
c.executemany('INSERT INTO access_events VALUES (?, ?, ?, ?, ?)', events)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
