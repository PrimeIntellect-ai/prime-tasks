#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()

c.execute('''
CREATE TABLE backup_lineage (
    id TEXT PRIMARY KEY,
    parent_id TEXT,
    backup_type TEXT,
    file_path TEXT,
    timestamp DATETIME
)
''')

data = [
    ('bkp_0001', None, 'full', '/backups/full/0001.tar.gz', '2023-10-01 00:00:00'),
    ('bkp_0002', 'bkp_0001', 'inc', '/backups/inc/0002.tar.gz', '2023-10-02 00:00:00'),
    ('bkp_0003', 'bkp_0001', 'inc', '/backups/inc/0003.tar.gz', '2023-10-03 00:00:00'),
    ('bkp_0004', 'bkp_0002', 'inc', '/backups/inc/0004.tar.gz', '2023-10-04 00:00:00'),
    ('bkp_0005', 'bkp_0002', 'inc', '/backups/inc/0005.tar.gz', '2023-10-05 00:00:00'),
    ('bkp_0006', 'bkp_0004', 'inc', '/backups/inc/0006.tar.gz', '2023-10-06 00:00:00'),
    ('bkp_0099', None, 'full', '/backups/full/0099.tar.gz', '2023-10-07 00:00:00'),
    ('bkp_0100', 'bkp_0099', 'inc', '/backups/inc/0100.tar.gz', '2023-10-08 00:00:00'),
]

c.executemany('INSERT INTO backup_lineage VALUES (?, ?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
