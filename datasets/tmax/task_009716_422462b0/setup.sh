#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/db_locks.sqlite'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# transactions table
cursor.execute('''
CREATE TABLE alpha_records (
    alpha_id INTEGER PRIMARY KEY,
    identifier TEXT NOT NULL,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP
)
''')

# held locks table
cursor.execute('''
CREATE TABLE beta_records (
    record_id INTEGER PRIMARY KEY,
    alpha_ref INTEGER,
    item_ref INTEGER
)
''')

# requested locks table
cursor.execute('''
CREATE TABLE gamma_records (
    record_id INTEGER PRIMARY KEY,
    alpha_ref INTEGER,
    item_ref INTEGER
)
''')

# Insert transactions
transactions = [
    (1, 'TX_Alpha'),
    (2, 'TX_Beta'),
    (3, 'TX_Gamma'),
    (4, 'TX_Delta'),
    (5, 'TX_Epsilon'),
    (6, 'TX_Zeta'),
    (7, 'TX_Eta')
]
cursor.executemany('INSERT INTO alpha_records (alpha_id, identifier) VALUES (?, ?)', transactions)

# Insert held locks
held = [
    (1, 1, 101),
    (2, 2, 102),
    (3, 3, 103),
    (4, 4, 104),
    (5, 5, 105)
]
cursor.executemany('INSERT INTO beta_records (record_id, alpha_ref, item_ref) VALUES (?, ?, ?)', held)

# Insert requested locks
requests = [
    (1, 2, 101),
    (2, 3, 102),
    (3, 1, 103),
    (4, 4, 102),
    (5, 5, 102),
    (6, 6, 104),
    (7, 7, 104),
    (8, 4, 105),
    (9, 5, 104)
]
cursor.executemany('INSERT INTO gamma_records (record_id, alpha_ref, item_ref) VALUES (?, ?, ?)', requests)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
