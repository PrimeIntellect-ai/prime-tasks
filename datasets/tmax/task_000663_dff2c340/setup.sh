#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backup_catalog.db'
os.makedirs(os.path.dirname(db_path), exist_ok=True)
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
    CREATE TABLE backups (
        id TEXT PRIMARY KEY,
        db_name TEXT,
        backup_type TEXT,
        parent_id TEXT,
        timestamp TEXT,
        size_mb INTEGER,
        duration_sec INTEGER
    )
''')

backups_data = [
    # Chain 1 for auth_prod (Old, superseded)
    ('bkp_01', 'auth_prod', 'FULL', None, '2023-10-20 00:00:00', 950, 180),
    ('bkp_02', 'auth_prod', 'INC', 'bkp_01', '2023-10-21 00:00:00', 100, 20),

    # Chain 2 for auth_prod (The correct active chain)
    ('bkp_10', 'auth_prod', 'FULL', None, '2023-10-26 00:00:00', 1000, 200),
    ('bkp_11', 'other_db', 'FULL', None, '2023-10-26 01:00:00', 5000, 800),
    ('bkp_12', 'auth_prod', 'INC', 'bkp_10', '2023-10-26 12:00:00', 200, 40),
    ('bkp_14', 'auth_prod', 'INC', 'bkp_12', '2023-10-27 00:00:00', 300, 60),
    ('bkp_18', 'auth_prod', 'INC', 'bkp_14', '2023-10-27 12:00:00', 50, 15),

    # Backup after the crash
    ('bkp_20', 'auth_prod', 'INC', 'bkp_18', '2023-10-28 00:00:00', 100, 30),

    # Another full backup for auth_prod taken after crash
    ('bkp_25', 'auth_prod', 'FULL', None, '2023-10-28 12:00:00', 1200, 220)
]

c.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?, ?, ?)', backups_data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
