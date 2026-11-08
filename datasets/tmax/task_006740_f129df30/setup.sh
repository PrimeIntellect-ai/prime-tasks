#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backup_catalog.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE clusters (id INTEGER PRIMARY KEY, name TEXT, region TEXT)''')
c.execute('''CREATE TABLE backups (id INTEGER PRIMARY KEY, cluster_id INTEGER, timestamp TEXT, size_bytes INTEGER, status TEXT)''')

clusters = [
    (1, 'db-prod-1', 'us-west-2'),
    (2, 'db-prod-2', 'us-west-2'),
    (3, 'db-dev-1', 'us-east-1'),
    (4, 'db-staging-1', 'us-west-2')
]
c.executemany("INSERT INTO clusters VALUES (?, ?, ?)", clusters)

backups = [
    # db-prod-1 (us-west-2)
    (101, 1, '2023-10-01T10:00:00Z', 1000, 'SUCCESS'),
    (102, 1, '2023-10-02T10:00:00Z', 1100, 'FAILED'),
    (103, 1, '2023-10-03T10:00:00Z', 1200, 'SUCCESS'),
    # db-prod-2 (us-west-2)
    (104, 2, '2023-10-01T11:00:00Z', 2000, 'SUCCESS'),
    (105, 2, '2023-10-02T11:00:00Z', 2100, 'SUCCESS'),
    (106, 2, '2023-10-03T11:00:00Z', 2200, 'FAILED'),
    # db-dev-1 (us-east-1)
    (107, 3, '2023-10-01T12:00:00Z', 500, 'SUCCESS'),
    # db-staging-1 (us-west-2) - all failed
    (108, 4, '2023-10-01T13:00:00Z', 800, 'FAILED')
]
c.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", backups)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
