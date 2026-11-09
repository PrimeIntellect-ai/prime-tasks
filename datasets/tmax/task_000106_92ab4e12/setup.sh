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
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE backups (
    backup_id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    size_bytes INTEGER,
    job_name TEXT
)
''')

data = [
    (1, None, 1048576, 'full_weekly'),
    (2, 1, 512000, 'inc_daily'),
    (3, 2, 256000, 'inc_daily'),
    (4, None, 2097152, 'full_weekly'),
    (5, 4, 128000, 'inc_daily'),
    (6, 3, 64000, 'inc_hourly'),
    (7, 1, 32000, 'inc_hourly'),
    (8, 7, 16000, 'inc_hourly'),
    (9, None, 512000, 'inc_daily')
]

cursor.executemany('INSERT INTO backups VALUES (?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
