#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import os

db_path = '/home/user/audit_logs.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, start_time DATETIME)')
c.execute('CREATE TABLE lock_requests (req_id INTEGER PRIMARY KEY, tx_id INTEGER, resource_id INTEGER, status TEXT)')

# Insert transactions
c.executemany('INSERT INTO transactions VALUES (?, ?)', [
    (1, '2022-12-01 10:00:00'),
    (2, '2023-01-05 10:00:00'),
    (3, '2023-01-05 10:05:00'),
    (4, '2023-01-06 11:00:00'),
    (5, '2023-01-06 11:05:00'),
    (6, '2023-01-07 12:00:00')
])

# Insert lock requests
requests = [
    # Deadlock 1: Tx 2 and Tx 3 (both > 2023-01-01) -> Expected
    (1, 2, 100, 'GRANTED'),
    (2, 3, 101, 'GRANTED'),
    (3, 2, 101, 'WAITING'),
    (4, 3, 100, 'WAITING'),

    # Deadlock 2: Tx 4 and Tx 5 (both > 2023-01-01) -> Expected
    (5, 4, 102, 'GRANTED'),
    (6, 5, 103, 'GRANTED'),
    (7, 4, 103, 'WAITING'),
    (8, 5, 102, 'WAITING'),

    # Not a deadlock: Tx 6 just waits for Tx 2
    (9, 6, 104, 'WAITING'),
    (10, 2, 104, 'GRANTED'),

    # Old deadlock: Tx 1 and Tx 2 (Tx 1 <= 2023-01-01) -> Should be filtered out
    (11, 1, 105, 'GRANTED'),
    (12, 2, 106, 'GRANTED'),
    (13, 1, 106, 'WAITING'),
    (14, 2, 105, 'WAITING')
]
c.executemany('INSERT INTO lock_requests VALUES (?, ?, ?, ?)', requests)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
