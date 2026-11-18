#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/financial_audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE accounts (
    account_id TEXT PRIMARY KEY,
    account_type TEXT,
    risk_score INTEGER
)
''')

c.execute('''
CREATE TABLE transactions (
    tx_id TEXT PRIMARY KEY,
    source_account TEXT,
    target_account TEXT,
    amount REAL
)
''')

accounts_data = [
    ('A1', 'domestic', 10),
    ('A2', 'domestic', 90),
    ('A3', 'domestic', 20),
    ('A4', 'domestic', 50),
    ('A5', 'offshore', 30),
    ('A6', 'domestic', 85),
    ('A7', 'offshore', 40),
    ('A8', 'domestic', 15)
]

transactions_data = [
    ('T1', 'A2', 'A1', 100),
    ('T2', 'A1', 'A3', 200),
    ('T3', 'A3', 'A5', 300),
    ('T4', 'A6', 'A4', 400),
    ('T5', 'A4', 'A1', 500),
    ('T6', 'A4', 'A7', 600),
    ('T7', 'A5', 'A2', 700),
    ('T8', 'A8', 'A6', 800),
    ('T9', 'A1', 'A8', 900)
]

c.executemany('INSERT INTO accounts VALUES (?, ?, ?)', accounts_data)
c.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?)', transactions_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
