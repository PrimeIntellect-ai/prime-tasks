#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/analytics.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE client_records (
    client_id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT
)
''')

c.execute('''
CREATE TABLE purchase_history (
    purchase_id INTEGER PRIMARY KEY,
    fk_client_id INTEGER,
    purchase_amount REAL,
    current_status TEXT,
    FOREIGN KEY(fk_client_id) REFERENCES client_records(client_id)
)
''')

c.execute('''
CREATE TABLE support_logs (
    log_id INTEGER PRIMARY KEY,
    fk_client_id INTEGER,
    duration_secs INTEGER,
    FOREIGN KEY(fk_client_id) REFERENCES client_records(client_id)
)
''')

# Insert Clients
clients = [
    (1, 'Alice Smith', 'alice@example.com'),
    (2, 'Bob Jones', 'bob@example.com'),
    (3, 'Charlie Brown', 'charlie@example.com'),
    (4, 'Diana Prince', 'diana@example.com') # No orders, no interactions
]
c.executemany("INSERT INTO client_records VALUES (?, ?, ?)", clients)

# Insert Orders
orders = [
    (101, 1, 250.0, 'completed'),
    (102, 1, 50.0, 'refunded'),
    (103, 2, 100.0, 'completed'),
    (104, 3, 300.0, 'completed'),
    (105, 3, 100.0, 'pending')
]
c.executemany("INSERT INTO purchase_history VALUES (?, ?, ?, ?)", orders)

# Insert Interactions
interactions = [
    (201, 1, 120),
    (202, 1, 45),
    (203, 2, 300),
    (204, 3, 15)
]
c.executemany("INSERT INTO support_logs VALUES (?, ?, ?)", interactions)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
