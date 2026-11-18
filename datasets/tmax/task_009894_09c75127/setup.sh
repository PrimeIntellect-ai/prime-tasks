#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the SQLite database and populate it with initial data
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/events.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)')
c.execute('CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, category TEXT, timestamp DATETIME)')

users = [
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com'),
    (3, 'Charlie', 'charlie@example.com')
]
c.executemany('INSERT INTO users VALUES (?, ?, ?)', users)

purchases = [
    (101, 1, 45.0, 'books', '2023-01-01 10:00:00'),
    (102, 1, 120.0, 'electronics', '2023-01-02 11:00:00'),
    (103, 1, 200.0, 'furniture', '2023-01-03 12:00:00'),
    (104, 2, 30.0, 'food', '2023-01-01 10:00:00'),
    (105, 2, 60.0, 'clothing', '2023-01-02 11:00:00'),
    (106, 2, 60.0, 'books', '2023-01-03 12:00:00'),
    (107, 3, 10.0, 'toys', '2023-01-01 10:00:00')
]
c.executemany('INSERT INTO purchases VALUES (?, ?, ?, ?, ?)', purchases)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
