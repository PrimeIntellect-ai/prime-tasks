#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup_db.py
import os
import sqlite3

os.makedirs('/home/user/data', exist_ok=True)
db_path = '/home/user/data/comms.db'

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.executescript("""
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department_id INTEGER);
CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME);

INSERT INTO departments (id, name) VALUES (1, 'Sales'), (2, 'Engineering'), (3, 'HR');

INSERT INTO users (id, name, department_id) VALUES 
(1, 'Alice', 1), (2, 'Bob', 1), (3, 'Charlie', 2), 
(4, 'Diana', 2), (5, 'Eve', 3), (6, 'Frank', 3);
""")

# Alice receives a lot of messages, acting as a central hub
messages = [
    # Alice <-> Bob
    (2, 1), (2, 1), (2, 1), (1, 2),
    # Charlie -> Diana
    (3, 4), (3, 4), (3, 4), (3, 4), (3, 4),
    # Diana -> Alice
    (4, 1), (4, 1),
    # Eve -> Frank
    (5, 6), (5, 6),
    # Frank -> Alice
    (6, 1)
]

for i, (s, r) in enumerate(messages, 1):
    cursor.execute(f"INSERT INTO messages (id, sender_id, receiver_id, timestamp) VALUES ({i}, {s}, {r}, '2023-10-01 10:00:00')")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
