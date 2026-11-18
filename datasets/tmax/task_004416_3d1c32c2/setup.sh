#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/company.db')
cursor = conn.cursor()

cursor.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)")
cursor.execute("CREATE TABLE messages (sender_id INTEGER, receiver_id INTEGER)")

employees = [
    (1, 'Alice', None),
    (2, 'Charlie', 1),
    (3, 'Dave', 2),
    (4, 'Eve', 3),
    (5, 'Frank', 4),
    (6, 'Bob', 5),
    (7, 'Grace', 1),
    (8, 'Heidi', 7)
]
cursor.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

messages = [
    (1, 3),
    (3, 5),
    (8, 6)
]
cursor.executemany("INSERT INTO messages VALUES (?, ?)", messages)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
