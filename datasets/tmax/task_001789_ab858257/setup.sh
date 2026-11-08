#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/etl_data.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE sales_raw (
    record_id INTEGER PRIMARY KEY,
    emp_id INTEGER,
    manager_id INTEGER,
    sales_amount REAL,
    updated_at TEXT
)
''')

records = [
    (1, 1, None, 100.0, '2023-10-01 10:00:00'),
    (2, 1, None, 150.0, '2023-10-01 12:00:00'),
    (3, 2, 1, 200.0, '2023-10-01 09:00:00'),
    (4, 2, 1, 220.0, '2023-10-01 11:00:00'),
    (5, 3, 1, 300.0, '2023-10-01 10:30:00'),
    (6, 4, 2, 50.0, '2023-10-01 08:00:00'),
    (7, 4, 2, 80.0, '2023-10-01 12:30:00'),
    (8, 5, 2, 120.0, '2023-10-01 10:00:00'),
    (9, 6, 4, 10.0, '2023-10-01 09:15:00'),
    (10, 7, 3, 40.0, '2023-10-01 07:00:00'),
    (11, 7, 3, 45.0, '2023-10-01 13:00:00'),
]

c.executemany('INSERT INTO sales_raw VALUES (?, ?, ?, ?, ?)', records)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
