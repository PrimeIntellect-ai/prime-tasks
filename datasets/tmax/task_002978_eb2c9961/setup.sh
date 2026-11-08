#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/financial_audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE wire_transfers (tx_id INTEGER PRIMARY KEY, sender TEXT, receiver TEXT, amount REAL, timestamp DATETIME)''')

data = [
    (1, 'Alice', 'Bob', 1000.0, '2023-01-01 10:00:00'),
    (2, 'Bob', 'Charlie', 1500.0, '2023-01-02 10:00:00'),
    (3, 'Charlie', 'Alice', 2000.0, '2023-01-03 10:00:00'),

    (4, 'Xavier', 'Yolanda', 5000.0, '2023-01-01 11:00:00'),
    (5, 'Yolanda', 'Zack', 5000.0, '2023-01-02 11:00:00'),
    (6, 'Zack', 'Xavier', 5000.0, '2023-01-03 11:00:00'),

    (7, 'Mona', 'Nina', 300.0, '2023-02-01 10:00:00'),
    (8, 'Nina', 'Oscar', 400.0, '2023-02-02 10:00:00'),
    (9, 'Oscar', 'Mona', 500.0, '2023-01-31 10:00:00'),

    (10, 'Dan', 'Eve', 100.0, '2023-03-01 10:00:00'),
    (11, 'Eve', 'Dan', 200.0, '2023-03-02 10:00:00')
]

c.executemany("INSERT INTO wire_transfers VALUES (?, ?, ?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
