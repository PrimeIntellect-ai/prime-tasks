#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/etl_locks.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''
    CREATE TABLE transactions (
        tx_id TEXT PRIMARY KEY,
        start_time DATETIME,
        query TEXT
    )
''')

cur.execute('''
    CREATE TABLE locks (
        tx_id TEXT,
        resource_id TEXT,
        status TEXT
    )
''')

# Insert transactions
tx_data = [
    ("T1", "2023-10-01 10:01:00", "UPDATE users SET active=1"),
    ("T2", "2023-10-01 10:02:00", "DELETE FROM sessions WHERE idle>10"),
    ("T3", "2023-10-01 10:03:00", "INSERT INTO logs VALUES (...)"),
    ("T4", "2023-10-01 10:04:00", "UPDATE config SET val=2"),
    ("T5", "2023-10-01 10:05:00", "SELECT * FROM orders"),
    ("T6", "2023-10-01 10:06:00", "UPDATE orders SET status='shipped'"),
    ("T7", "2023-10-01 10:07:00", "SELECT * FROM users"),
    ("T8", "2023-10-01 10:08:00", "DELETE FROM temp_data"),
    ("T9", "2023-10-01 10:09:00", "INSERT INTO metrics VALUES (...)"),
    ("T10", "2023-10-01 10:10:00", "UPDATE stats SET count=count+1"),
    ("T11", "2023-10-01 10:11:00", "UPDATE stats_agg SET total=total+1")
]
cur.executemany("INSERT INTO transactions VALUES (?, ?, ?)", tx_data)

# Insert locks
locks_data = [
    ("T1", "R1", "GRANTED"),
    ("T1", "R4", "WAITING"),
    ("T2", "R2", "GRANTED"),
    ("T2", "R1", "WAITING"),
    ("T3", "R3", "GRANTED"),
    ("T3", "R2", "WAITING"),
    ("T4", "R4", "GRANTED"),
    ("T4", "R3", "WAITING"),
    ("T5", "R5", "GRANTED"),
    ("T6", "R5", "WAITING"),
    ("T7", "R6", "GRANTED"),
    ("T8", "R7", "GRANTED"),
    ("T8", "R6", "WAITING"),
    ("T9", "R7", "WAITING"),
    ("T10", "R8", "GRANTED"),
    ("T10", "R9", "WAITING"),
    ("T11", "R9", "GRANTED"),
    ("T11", "R8", "WAITING")
]
cur.executemany("INSERT INTO locks VALUES (?, ?, ?)", locks_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
