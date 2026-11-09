#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    # Create the SQLite database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()
c.execute('''CREATE TABLE backup_jobs (
    id INTEGER PRIMARY KEY, 
    db_name TEXT, 
    start_time DATETIME, 
    size_bytes INTEGER, 
    parent_backup_id INTEGER, 
    status TEXT)''')

# Insert data
data = [
    (1, 'auth_db', '2023-10-01 00:00:00', 100, None, 'SUCCESS'),
    (2, 'auth_db', '2023-10-02 00:00:00', 10, 1, 'SUCCESS'),
    (3, 'auth_db', '2023-10-03 00:00:00', 15, 2, 'SUCCESS'),

    (4, 'auth_db', '2023-10-08 00:00:00', 110, None, 'SUCCESS'),
    (5, 'auth_db', '2023-10-09 00:00:00', 20, 4, 'SUCCESS'),

    (6, 'auth_db', '2023-10-15 00:00:00', 250, None, 'SUCCESS'),
    (7, 'auth_db', '2023-10-16 00:00:00', 50, 6, 'SUCCESS'),

    (8, 'users_db', '2023-10-01 00:00:00', 500, None, 'SUCCESS'),
    (9, 'users_db', '2023-10-08 00:00:00', 550, None, 'SUCCESS'),
    (10, 'users_db', '2023-10-15 00:00:00', 600, None, 'SUCCESS'),
]

c.executemany("INSERT INTO backup_jobs VALUES (?, ?, ?, ?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    # Execute the setup script and clean up
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Set permissions
    chmod -R 777 /home/user
