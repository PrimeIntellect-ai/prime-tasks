#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/finances.db')
c = conn.cursor()

c.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY, sender TEXT, receiver TEXT, amount REAL, tx_date DATETIME)")

# Insert transactions
transactions = [
    # High Risk Sender 'Alice' (averages > 50000 in her last 3 transactions)
    (1, 'Alice', 'David', 10000, '2023-01-01 10:00:00'),
    (2, 'Alice', 'Eve', 60000, '2023-01-02 10:00:00'),
    (3, 'Alice', 'Bob', 90000, '2023-01-03 10:00:00'), # Moving avg of 1,2,3 is 53333.33 -> High Risk!

    # Cycle 1: Alice -> Bob -> Charlie -> Alice (Length 3, contains High Risk 'Alice')
    (4, 'Bob', 'Charlie', 5000, '2023-01-04 10:00:00'),
    (5, 'Charlie', 'Alice', 5000, '2023-01-05 10:00:00'),

    # Cycle 2: Xander -> Yasmine -> Zane -> Xander (Length 3, NO High Risk senders)
    (6, 'Xander', 'Yasmine', 20000, '2023-01-06 10:00:00'),
    (7, 'Yasmine', 'Zane', 20000, '2023-01-07 10:00:00'),
    (8, 'Zane', 'Xander', 20000, '2023-01-08 10:00:00'),

    # Noise
    (9, 'Frank', 'Grace', 100000, '2023-01-09 10:00:00'), # High risk but no cycle
    (10, 'Frank', 'Grace', 100000, '2023-01-10 10:00:00'),
    (11, 'Frank', 'Grace', 100000, '2023-01-11 10:00:00')
]

c.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", transactions)

# Create the index
c.execute("CREATE INDEX idx_sender ON transactions(sender)")
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
