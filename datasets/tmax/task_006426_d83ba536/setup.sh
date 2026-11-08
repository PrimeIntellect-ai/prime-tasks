#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3
import json

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()

c.execute('''
    CREATE TABLE backup_events (
        id INTEGER PRIMARY KEY,
        dataset TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        parent_id INTEGER,
        metadata TEXT
    )
''')

backups = [
    # dataset 'users'
    (1, 'users', 1000, 'full', None, json.dumps({"status": "archived", "size_bytes": 5000})),
    (2, 'users', 1010, 'incremental', 1, json.dumps({"status": "archived", "size_bytes": 500})),
    (3, 'users', 1020, 'incremental', 2, json.dumps({"status": "archived", "size_bytes": 600})),
    (4, 'users', 2000, 'full', None, json.dumps({"status": "active", "size_bytes": 5500})),
    (5, 'users', 2010, 'incremental', 4, json.dumps({"status": "active", "size_bytes": 100})),

    # dataset 'orders'
    (6, 'orders', 1500, 'full', None, json.dumps({"status": "archived", "size_bytes": 10000})),
    (7, 'orders', 1510, 'incremental', 6, json.dumps({"status": "archived", "size_bytes": 1000})),
    (8, 'orders', 1520, 'incremental', 7, json.dumps({"status": "archived", "size_bytes": 1200})),
    (9, 'orders', 1530, 'incremental', 8, json.dumps({"status": "failed", "size_bytes": 0})),
    (10, 'orders', 1540, 'incremental', 8, json.dumps({"status": "active", "size_bytes": 1300})), # chain length 3
    (11, 'orders', 1550, 'incremental', 10, json.dumps({"status": "active", "size_bytes": 1400})), # chain length 4

    # dataset 'inventory'
    (12, 'inventory', 3000, 'full', None, json.dumps({"status": "active", "size_bytes": 2000}))
]

c.executemany('INSERT INTO backup_events VALUES (?, ?, ?, ?, ?, ?)', backups)
conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
