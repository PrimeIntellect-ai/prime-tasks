#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backups.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE servers (server_id INTEGER PRIMARY KEY, hostname TEXT)''')
c.execute('''CREATE TABLE jobs (job_id INTEGER PRIMARY KEY, server_id INTEGER, parent_id INTEGER, size_bytes INTEGER, type TEXT)''')
c.execute('''CREATE INDEX idx_parent ON jobs(parent_id)''')

servers = [
    (1, 'db-prod-01'),
    (2, 'web-front-02'),
    (3, 'cache-node-01')
]
c.executemany("INSERT INTO servers VALUES (?, ?)", servers)

jobs = [
    (1, 1, None, 4000, 'FULL'),
    (2, 1, 1, 1000, 'INC'),
    (3, 1, 2, 500, 'INC'),
    (4, 2, None, 3000, 'FULL'),
    (5, 2, 4, 1000, 'INC'),
    (6, 1, None, 8000, 'FULL'),
    (7, 1, 6, 2000, 'INC'),
    (8, 3, None, 5001, 'FULL')
]
c.executemany("INSERT INTO jobs VALUES (?, ?, ?, ?, ?)", jobs)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
