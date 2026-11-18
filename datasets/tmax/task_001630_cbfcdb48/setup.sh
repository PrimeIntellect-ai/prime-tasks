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
db_path = '/home/user/transaction_logs.db'

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE events (event_id INTEGER PRIMARY KEY, tx_id TEXT, resource_id TEXT, action TEXT, event_time INTEGER)''')

events = [
    (1, 'T1', 'R1', 'HOLD', 10),
    (2, 'T2', 'R2', 'HOLD', 11),
    (3, 'T1', 'R2', 'WAIT', 12),
    (4, 'T2', 'R1', 'WAIT', 13),

    (5, 'T3', 'R3', 'HOLD', 14),
    (6, 'T4', 'R4', 'HOLD', 15),
    (7, 'T5', 'R5', 'HOLD', 16),
    (8, 'T3', 'R4', 'WAIT', 17),
    (9, 'T4', 'R5', 'WAIT', 18),
    (10, 'T5', 'R3', 'WAIT', 19),

    (11, 'T6', 'R6', 'HOLD', 20),
    (12, 'T6', 'R6', 'RELEASE', 21),
    (13, 'T7', 'R7', 'HOLD', 22),
    (14, 'T7', 'R6', 'WAIT', 23),

    (15, 'T8', 'R8', 'WAIT', 24),
    (16, 'T8', 'R8', 'HOLD', 25),

    (17, 'T9', 'R9', 'HOLD', 26),
    (18, 'T9', 'R10', 'WAIT', 27),
    (19, 'T10', 'R10', 'HOLD', 28),
    (20, 'T10', 'R10', 'RELEASE', 29)
]

c.executemany('INSERT INTO events VALUES (?,?,?,?,?)', events)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
