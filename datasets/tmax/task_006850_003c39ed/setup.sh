#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/transactions.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("CREATE TABLE locks (tx_id TEXT, resource TEXT, state TEXT)")

data = [
    ('T1', 'R1', 'GRANTED'),
    ('T2', 'R1', 'WAITING'),
    ('T2', 'R2', 'GRANTED'),
    ('T3', 'R2', 'WAITING'),
    ('T3', 'R3', 'GRANTED'),
    ('T1', 'R3', 'WAITING'),

    ('T4', 'R4', 'GRANTED'),
    ('T5', 'R4', 'WAITING'),
    ('T5', 'R5', 'GRANTED'),
    ('T4', 'R5', 'WAITING'),

    ('T6', 'R6', 'GRANTED'),
    ('T7', 'R6', 'WAITING'),
    ('T8', 'R6', 'WAITING'),
    ('T9', 'R6', 'WAITING'),
]

cur.executemany("INSERT INTO locks VALUES (?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
