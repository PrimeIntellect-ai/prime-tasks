#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/backup_metadata.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE backups (
    id TEXT PRIMARY KEY,
    type TEXT,
    timestamp DATETIME,
    size_mb INTEGER,
    parent_id TEXT
)
''')

backups_data = [
    ('bkp_001', 'FULL', '2023-11-01 00:00:00', 5000, None),
    ('bkp_002', 'INCREMENTAL', '2023-11-02 00:00:00', 150, 'bkp_001'),
    ('bkp_003', 'INCREMENTAL', '2023-11-03 00:00:00', 200, 'bkp_002'),
    ('bkp_004', 'INCREMENTAL', '2023-11-04 00:00:00', 180, 'bkp_003'),
    ('bkp_005', 'FULL', '2023-11-05 00:00:00', 5200, None),
    ('bkp_006', 'INCREMENTAL', '2023-11-05 12:00:00', 50, 'bkp_005'),
    ('bkp_007', 'INCREMENTAL', '2023-11-05 18:00:00', 70, 'bkp_006'),
    ('bkp_008', 'INCREMENTAL', '2023-11-06 00:00:00', 120, 'bkp_007')
]

cursor.executemany('''
INSERT INTO backups (id, type, timestamp, size_mb, parent_id)
VALUES (?, ?, ?, ?, ?)
''', backups_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
