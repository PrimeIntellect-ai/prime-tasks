#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import sqlite3

conn = sqlite3.connect('/home/user/backup_catalog.db')
c = conn.cursor()
c.execute('''CREATE TABLE backup_jobs (job_id INTEGER PRIMARY KEY, job_name TEXT, parent_job_id INTEGER, size_bytes INTEGER, status TEXT)''')

jobs = [
    (5, 'Full_DB_Backup_Jan1', None, 5000000, 'SUCCESS'),
    (12, 'Inc_DB_Backup_Jan2', 5, 100000, 'SUCCESS'),
    (24, 'Inc_DB_Backup_Jan3', 12, 120000, 'SUCCESS'),
    (45, 'Inc_DB_Backup_Jan4', 24, 150000, 'SUCCESS'),
    (73, 'Inc_DB_Backup_Jan5', 45, 90000, 'SUCCESS'),
    (80, 'Inc_DB_Backup_Jan6', 73, 110000, 'SUCCESS'),
    (10, 'Full_DB_Backup_Feb1', None, 5200000, 'SUCCESS'),
    (15, 'Inc_DB_Backup_Feb2', 10, 80000, 'SUCCESS')
]

c.executemany("INSERT INTO backup_jobs VALUES (?, ?, ?, ?, ?)", jobs)
conn.commit()
conn.close()
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
