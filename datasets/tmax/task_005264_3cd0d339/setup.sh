#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/transactions.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE transfers (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp TEXT)')
transfers = [
    # Cycle 1: 10, 20, 30, 40
    (1, 10, 20, 100, '2023-01-01'),
    (2, 20, 30, 100, '2023-01-01'),
    (3, 30, 40, 100, '2023-01-01'),
    (4, 40, 10, 100, '2023-01-01'),
    # Cycle 2: 1, 2, 3, 4
    (5, 1, 2, 50, '2023-01-01'),
    (6, 2, 3, 50, '2023-01-01'),
    (7, 3, 4, 50, '2023-01-01'),
    (8, 4, 1, 50, '2023-01-01'),
    # Noise
    (9, 4, 5, 50, '2023-01-01'),
    (10, 20, 25, 50, '2023-01-01'),
    (11, 25, 26, 50, '2023-01-01'),
    (12, 26, 20, 50, '2023-01-01'), # Cycle of 3
]
c.executemany('INSERT INTO transfers VALUES (?, ?, ?, ?, ?)', transfers)
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
