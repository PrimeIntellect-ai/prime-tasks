#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the setup script for the database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('''CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, owner_name TEXT, region TEXT)''')
c.execute('''CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, tx_timestamp DATETIME)''')

accounts = [
    (1, 'Alice Corp', 'NA'),
    (2, 'Bob LLC', 'NA'),
    (3, 'Charlie Inc', 'EU'),
    (4, 'Delta Co', 'AS'),
    (5, 'Echo Ltd', 'AS'),
    (6, 'Foxtrot SA', 'EU'),
    (7, 'Golf NV', 'NA')
]
c.executemany("INSERT INTO accounts VALUES (?, ?, ?)", accounts)

transactions = [
    # Circle 1: 1 -> 2 -> 3 -> 1 (Alice sent 500)
    (101, 1, 2, 500.0, '2023-01-01 10:00:00'),
    (102, 2, 3, 490.0, '2023-01-01 11:00:00'),
    (103, 3, 1, 480.0, '2023-01-01 12:00:00'),

    # Circle 2: 4 -> 5 -> 6 -> 4 (Delta sent 1200)
    (104, 4, 5, 1200.0, '2023-01-02 09:00:00'),
    (105, 5, 6, 1150.0, '2023-01-02 10:00:00'),
    (106, 6, 4, 1100.0, '2023-01-02 11:00:00'),

    # Circle 3: 1 -> 5 -> 7 -> 1 (Alice sent 200)
    (107, 1, 5, 200.0, '2023-01-03 14:00:00'),
    (108, 5, 7, 190.0, '2023-01-03 15:00:00'),
    (109, 7, 1, 180.0, '2023-01-03 16:00:00'),

    # Noise / Non-circular
    (110, 2, 4, 300.0, '2023-01-04 09:00:00'),
    (111, 4, 1, 150.0, '2023-01-04 10:00:00'), # Invalid time sequence for circle

    # Invalid circle (wrong time sequence) 7 -> 2 -> 4 -> 7
    (112, 7, 2, 800.0, '2023-01-05 12:00:00'),
    (113, 2, 4, 750.0, '2023-01-05 10:00:00'), # Before previous
    (114, 4, 7, 700.0, '2023-01-05 13:00:00')
]
c.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", transactions)
conn.commit()
conn.close()
EOF

    # Run the setup script
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Set permissions
    chmod -R 777 /home/user
