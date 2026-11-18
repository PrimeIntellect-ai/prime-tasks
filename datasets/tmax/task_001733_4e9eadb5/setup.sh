#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import json

conn = sqlite3.connect('/home/user/app.db')
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,
    parent_account_id INTEGER
)
''')

cursor.execute('''
CREATE TABLE logs (
    log_id INTEGER PRIMARY KEY,
    account_id INTEGER,
    data TEXT,
    created_at DATETIME
)
''')

accounts_data = [
    (1, None),
    (2, 1),
    (3, 2),
    (4, None),
    (5, 4),
    (6, 4)
]
cursor.executemany("INSERT INTO accounts VALUES (?, ?)", accounts_data)

logs_data = [
    (1, 1, '{"query_time_ms": 10}', '2023-01-01 10:00:00'),
    (2, 1, '{"query_time_ms": 20}', '2023-01-01 10:01:00'),
    (3, 2, '{"query_time_ms": 60}', '2023-01-01 10:00:00'),
    (4, 2, '{"query_time_ms": 60}', '2023-01-01 10:01:00'),
    (5, 3, '{"query_time_ms": 100}', '2023-01-01 10:00:00'),
    (6, 3, '{"query_time_ms": 15}', '2023-01-01 10:01:00'),
    (7, 4, '{"query_time_ms": 200}', '2023-01-01 10:00:00'),
    (8, 4, '{"query_time_ms": 50}', '2023-01-01 10:01:00'),
    (9, 5, '{"query_time_ms": 30}', '2023-01-01 10:00:00'),
    (10, 5, '{"query_time_ms": 10}', '2023-01-01 10:01:00'),
    (11, 6, '{"query_time_ms": 80}', '2023-01-01 10:00:00'),
    (12, 6, '{"query_time_ms": 25}', '2023-01-01 10:01:00')
]
cursor.executemany("INSERT INTO logs VALUES (?, ?, ?, ?)", logs_data)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py
    chown -R user:user /home/user

    chmod -R 777 /home/user
