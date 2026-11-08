#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/papers.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)')
c.execute('CREATE TABLE citations (citer_id INTEGER, cited_id INTEGER)')

for i in range(1, 10):
    c.execute('INSERT INTO papers (id, title, year) VALUES (?, ?, ?)', (i, f'Paper {i}', 2000 + i))
c.execute('INSERT INTO papers (id, title, year) VALUES (?, ?, ?)', (100, 'Paper 100', 2020))

citations = [
    (2, 1),
    (3, 1),
    (4, 1),
    (5, 2),
    (6, 4),
    (7, 5),
    (100, 6),
    (100, 7),
    (9, 8)
]
c.executemany('INSERT INTO citations VALUES (?, ?)', citations)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
