#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backups.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE backup_catalog (
    id INTEGER PRIMARY KEY,
    db_name TEXT,
    backup_type TEXT,
    parent_id INTEGER,
    size_bytes INTEGER,
    timestamp DATETIME
)
''')

# Insert data
data = [
    # Old chain for prod_payments
    (1, 'prod_payments', 'FULL', None, 5000, '2023-10-01 00:00:00'),
    (2, 'prod_payments', 'INC', 1, 500, '2023-10-02 00:00:00'),
    (3, 'prod_payments', 'INC', 2, 600, '2023-10-03 00:00:00'),

    # Unrelated DB
    (4, 'prod_users', 'FULL', None, 2000, '2023-11-01 00:00:00'),

    # Newest chain for prod_payments
    (5, 'prod_payments', 'FULL', None, 5200, '2023-11-05 00:00:00'),
    (6, 'prod_payments', 'INC', 5, 100, '2023-11-06 00:00:00'),
    (7, 'prod_payments', 'INC', 6, 250, '2023-11-07 00:00:00'),
    (8, 'prod_payments', 'INC', 7, 150, '2023-11-08 00:00:00'),

    # Broken/Orphaned chain just to add noise
    (9, 'prod_payments', 'INC', 999, 100, '2023-11-09 00:00:00')
]

cursor.executemany('INSERT INTO backup_catalog VALUES (?, ?, ?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
