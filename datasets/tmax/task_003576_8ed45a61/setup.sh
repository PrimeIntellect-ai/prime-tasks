#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Create the SQLite database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/app/research.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT, author TEXT, year INTEGER)')
cur.execute('CREATE TABLE citations(source_id INTEGER, target_id INTEGER)')

papers = [
    (1, 'Paper A', 'Alice', 2020),
    (2, 'Paper B', 'Alice', 2021),
    (3, 'Paper C', 'Alice', 2021),
    (4, 'Paper D', 'Alice', 2022),
    (5, 'Paper E', 'Alice', 2023),
    (6, 'Paper F', 'Bob', 2020),
    (7, 'Paper G', 'Bob', 2021)
]
cur.executemany('INSERT INTO papers VALUES(?, ?, ?, ?)', papers)

citations = [
    (6, 1), (7, 1), (2, 1), (3, 1), (4, 1),
    (1, 2), (6, 2), (7, 2), (3, 2),
    (1, 3), (2, 3), (6, 3),
    (1, 4), (2, 4), (7, 4),
    (2, 5),
    (1, 6), (2, 6), (3, 6), (4, 6), (5, 6), (1, 7)
]
cur.executemany('INSERT INTO citations VALUES(?, ?)', citations)

cur.execute('CREATE INDEX idx_cit ON citations(target_id)')
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    # Generate the audio file
    espeak -w /app/instructions.wav "secret graph dataset"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
