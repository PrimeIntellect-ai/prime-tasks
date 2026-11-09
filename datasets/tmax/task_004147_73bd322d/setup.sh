#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/locks.db')
cursor = conn.cursor()
cursor.execute('''CREATE TABLE waits_for (waiting_tx INTEGER, blocking_tx INTEGER)''')

edges = [
    (1, 2),
    (2, 3),
    (3, 1),
    (4, 5),
    (5, 6),
    (7, 8),
    (8, 9),
    (9, 7),
    (10, 2),
    (11, 11),
    (12, 13),
    (13, 14),
    (14, 12),
    (13, 15),
    (15, 14)
]

cursor.executemany('INSERT INTO waits_for VALUES (?, ?)', edges)
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
