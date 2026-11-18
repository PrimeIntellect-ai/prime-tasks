#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import datetime

conn = sqlite3.connect('/home/user/legacy_system.db')
cursor = conn.cursor()

# Create tables with obscure names to force reverse engineering
cursor.execute('''
CREATE TABLE tbl_acc (
    id TEXT PRIMARY KEY,
    owner_name TEXT
)
''')

cursor.execute('''
CREATE TABLE tbl_xfer (
    tx_id INTEGER PRIMARY KEY,
    src TEXT,
    dst TEXT,
    amt REAL,
    ts DATETIME
)
''')

# Insert data
# Cycle 1: Valid compliance violation (within 60s)
# tx_id 101, 102, 103
cursor.executemany('INSERT INTO tbl_xfer VALUES (?, ?, ?, ?, ?)', [
    (101, 'ACC_X1', 'ACC_X2', 100.0, '2023-10-01 10:00:00'),
    (102, 'ACC_X2', 'ACC_X3', 50.0,  '2023-10-01 10:00:15'),
    (103, 'ACC_X3', 'ACC_X1', 75.0,  '2023-10-01 10:00:45'), # Diff is 45s

    # Cycle 2: Invalid (takes longer than 60s)
    (104, 'ACC_Y1', 'ACC_Y2', 200.0, '2023-10-01 11:00:00'),
    (105, 'ACC_Y2', 'ACC_Y3', 200.0, '2023-10-01 11:01:30'),
    (106, 'ACC_Y3', 'ACC_Y1', 200.0, '2023-10-01 11:02:00'), # Diff is 120s

    # Random noise
    (107, 'ACC_Z1', 'ACC_Z2', 10.0, '2023-10-01 12:00:00'),
    (108, 'ACC_Z2', 'ACC_Z3', 10.0, '2023-10-01 12:00:10')
])

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
