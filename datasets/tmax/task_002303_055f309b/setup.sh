#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/citations.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, year INTEGER)")
c.execute("CREATE TABLE citations (citing_paper_id INTEGER, cited_paper_id INTEGER)")

authors = [
    (1, "Alice"),
    (2, "Bob"),
    (3, "Charlie"),
    (4, "Dave")
]
c.executemany("INSERT INTO authors VALUES (?, ?)", authors)

papers = [
    (1, "Paper A", 1, 2020),
    (2, "Paper B", 2, 2021),
    (3, "Paper C", 3, 2022),
    (4, "Paper D", 4, 2023),
    (5, "Paper E", 1, 2023)
]
c.executemany("INSERT INTO papers VALUES (?, ?, ?, ?)", papers)

# 2 cites 1
# 3 cites 2
# 4 cites 3
# 5 cites 2
citations = [
    (2, 1),
    (3, 2),
    (4, 3),
    (5, 2)
]
c.executemany("INSERT INTO citations VALUES (?, ?)", citations)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
