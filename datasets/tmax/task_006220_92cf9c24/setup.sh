#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = "/home/user/network.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
    CREATE TABLE IF NOT EXISTS links (
        src INTEGER,
        dst INTEGER,
        bandwidth INTEGER
    )
''')

edges = [
    (1, 2, 10),
    (2, 3, 15),
    (3, 1, 5),
    (2, 4, 20),
    (4, 1, 10),
    (3, 4, 25),
    (4, 5, 30),
    (5, 3, 5),
    (6, 7, 50),
    (7, 8, 40),
    (8, 9, 30)
]

cursor.executemany('INSERT INTO links VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
