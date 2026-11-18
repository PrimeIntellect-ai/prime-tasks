#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/backup_metadata.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    cluster_id TEXT,
    type TEXT,
    parent_id INTEGER,
    duration_sec INTEGER,
    timestamp DATETIME
)
''')

data = [
    # Cluster A (Normal)
    (1, 'cluster_A', 'full', None, 100, '2023-10-01 00:00:00'),
    (2, 'cluster_A', 'incremental', 1, 10, '2023-10-02 00:00:00'),
    (3, 'cluster_A', 'incremental', 1, 12, '2023-10-03 00:00:00'),
    (4, 'cluster_A', 'incremental', 1, 11, '2023-10-04 00:00:00'),
    (5, 'cluster_A', 'incremental', 1, 13, '2023-10-05 00:00:00'),

    # Cluster B (Anomaly)
    (6, 'cluster_B', 'full', None, 200, '2023-10-01 01:00:00'),
    (7, 'cluster_B', 'incremental', 6, 20, '2023-10-02 01:00:00'),
    (8, 'cluster_B', 'incremental', 6, 25, '2023-10-03 01:00:00'),
    (9, 'cluster_B', 'incremental', 6, 22, '2023-10-04 01:00:00'),
    (10, 'cluster_B', 'incremental', 6, 60, '2023-10-05 01:00:00'),
    (11, 'cluster_B', 'incremental', 6, 24, '2023-10-06 01:00:00'),

    # Cluster C (Critical node)
    (12, 'cluster_C', 'full', None, 500, '2023-10-01 02:00:00'),
    (13, 'cluster_C', 'incremental', 12, 15, '2023-10-02 02:00:00'),
    (14, 'cluster_C', 'incremental', 12, 16, '2023-10-03 02:00:00'),
    (15, 'cluster_C', 'incremental', 12, 14, '2023-10-04 02:00:00'),
    (16, 'cluster_C', 'incremental', 12, 15, '2023-10-05 02:00:00'),
    (17, 'cluster_C', 'incremental', 12, 16, '2023-10-06 02:00:00'),
    (18, 'cluster_C', 'incremental', 12, 17, '2023-10-07 02:00:00')
]

c.executemany('INSERT INTO backups VALUES (?,?,?,?,?,?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
