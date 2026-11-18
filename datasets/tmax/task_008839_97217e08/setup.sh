#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/supply_chain.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''CREATE TABLE facilities (id INTEGER PRIMARY KEY, name TEXT UNIQUE)''')
cursor.execute('''CREATE TABLE links (id INTEGER PRIMARY KEY, src_id INTEGER, dst_id INTEGER, cost INTEGER, is_active INTEGER)''')

# Insert facilities
facilities = [
    (1, 'Alpha_Manufacturing'),
    (2, 'Beta_Hub'),
    (3, 'Gamma_Depot'),
    (4, 'Delta_Transit'),
    (5, 'Omega_Distribution')
]
cursor.executemany("INSERT INTO facilities VALUES (?, ?)", facilities)

# Insert links
links = [
    (1, 1, 2, 10, 1),
    (2, 2, 3, 15, 1),
    (3, 3, 5, 20, 1),
    (4, 1, 4, 5, 1),
    (5, 4, 5, 50, 1),
    (6, 1, 5, 2, 0),
    (7, 2, 5, 5, 0)
]
cursor.executemany("INSERT INTO links VALUES (?, ?, ?, ?, ?)", links)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
