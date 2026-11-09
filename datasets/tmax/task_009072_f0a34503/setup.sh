#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/data.db'

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE users (user_id TEXT PRIMARY KEY)')
c.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender TEXT, receiver TEXT, amount REAL, timestamp TEXT)')

users = [(f'user_{i}',) for i in range(1, 11)]
c.executemany('INSERT INTO users VALUES (?)', users)

transactions = [
    (1, 'user_1', 'user_2', 10.0, '2023-01-01T10:00:00'),
    (2, 'user_2', 'user_3', 20.0, '2023-01-02T10:00:00'),
    (3, 'user_3', 'user_9', 30.0, '2023-01-03T10:00:00'),
    (4, 'user_1', 'user_5', 15.0, '2023-01-01T11:00:00'),
    (5, 'user_5', 'user_6', 25.0, '2023-01-02T11:00:00'),
    (6, 'user_5', 'user_9', 40.0, '2023-01-04T10:00:00'),
    (7, 'user_9', 'user_10', 50.0, '2023-01-05T10:00:00'),
    (8, 'user_9', 'user_2', 60.0, '2023-01-06T10:00:00'),
]
c.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)
conn.commit()
conn.close()

buggy_script = """import sqlite3
import csv

def run_pipeline():
    conn = sqlite3.connect('/home/user/data.db')
    c = conn.cursor()

    # BUG: Implicit cross join, missing join conditions!
    # Missing cumulative_sent window function
    query = '''
    SELECT 
        u1.user_id AS sender, 
        u2.user_id AS receiver, 
        t.amount, 
        t.timestamp
    FROM users u1, users u2, transactions t
    '''

    c.execute(query)
    rows = c.fetchall()

    with open('/home/user/edges.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['sender', 'receiver', 'amount', 'timestamp'])
        writer.writerows(rows)

if __name__ == '__main__':
    run_pipeline()
"""

with open('/home/user/etl_pipeline.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
