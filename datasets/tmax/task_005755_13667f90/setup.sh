#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
conn = sqlite3.connect('/home/user/company_data.db')
c = conn.cursor()

c.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)''')
c.execute('''CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, sent_at TEXT)''')

users = [
    (1, 'Alice', 'Engineering'),
    (2, 'Bob', 'HR'),
    (3, 'Charlie', 'Engineering'),
    (4, 'Diana', 'Marketing'),
    (5, 'Eve', 'Sales')
]
c.executemany('INSERT INTO users VALUES (?, ?, ?)', users)

messages = [
    (1, 1, 2, '2023-01-15'),
    (2, 3, 2, '2023-01-16'),
    (3, 4, 2, '2023-02-01'),
    (4, 1, 2, '2023-02-15'), # Duplicate edge 1->2
    (5, 2, 1, '2023-03-10'),
    (6, 4, 1, '2023-03-11'),
    (7, 5, 1, '2023-04-01'), # Outside test range
    (8, 3, 5, '2023-02-20'),
    (9, 4, 5, '2023-02-21'),
    (10, 1, 3, '2023-01-10')
]
c.executemany('INSERT INTO messages VALUES (?, ?, ?, ?)', messages)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
