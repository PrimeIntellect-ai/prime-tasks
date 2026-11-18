#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/compliance.db')
c = conn.cursor()

c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, country_code TEXT)')
c.execute('CREATE TABLE transactions (tx_id TEXT PRIMARY KEY, user_id INTEGER, amount REAL, tx_timestamp DATETIME)')
c.execute('CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, user_id INTEGER, ip_address TEXT, ip_country TEXT, log_timestamp DATETIME)')

users = [
    (1, 'US'),
    (2, 'UK'),
    (3, 'CA')
]
c.executemany('INSERT INTO users VALUES (?, ?)', users)

transactions = [
    ('TX001', 1, 15000.00, '2023-10-01 12:00:00'),
    ('TX002', 2, 20000.00, '2023-10-05 08:00:00'),
    ('TX003', 3, 5000.00,  '2023-10-10 15:00:00'),
    ('TX004', 1, 12000.00, '2023-10-20 10:00:00')
]
c.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?)', transactions)

access_logs = [
    (1, 1, '192.168.1.1', 'US', '2023-10-01 10:00:00'),
    (2, 1, '203.0.113.5', 'RU', '2023-10-01 14:00:00'),
    (3, 2, '198.51.100.2', 'FR', '2023-10-02 08:00:00'),
    (4, 3, '203.0.113.6', 'CN', '2023-10-10 16:00:00'),
    (5, 1, '192.168.1.2', 'US', '2023-10-20 09:00:00')
]
c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)', access_logs)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
