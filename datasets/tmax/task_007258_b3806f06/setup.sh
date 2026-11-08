#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/publications.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE papers (row_id INTEGER PRIMARY KEY, paper_id INTEGER, title TEXT, updated_at INTEGER)")
c.execute("CREATE TABLE authors (author_id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER)")
c.execute("CREATE TABLE citations (row_id INTEGER PRIMARY KEY, source_paper_id INTEGER, target_paper_id INTEGER, is_active INTEGER, updated_at INTEGER)")

# Authors
authors = [
    (1, "Alice Smith"),
    (2, "Bob Jones"),
    (3, "Charlie Brown"),
    (4, "Diana Prince")
]
c.executemany("INSERT INTO authors VALUES (?, ?)", authors)

# Paper authors
p_authors = [
    (1, 1),
    (2, 2),
    (3, 1), (3, 2),
    (4, 3),
    (5, 4)
]
c.executemany("INSERT INTO paper_authors VALUES (?, ?)", p_authors)

# Papers (with stale rows)
papers = [
    (1, 1, "Paper One Old", 100),
    (2, 1, "Paper One Final", 200),
    (3, 2, "Paper Two", 150),
    (4, 3, "Paper Three Old", 100),
    (5, 3, "Paper Three Final", 300),
    (6, 4, "Paper Four", 120),
    (7, 5, "Paper Five", 110)
]
c.executemany("INSERT INTO papers VALUES (?, ?, ?, ?)", papers)

# Citations (with stale rows)
citations = [
    (1, 1, 3, 1, 100),
    (2, 1, 3, 0, 150),
    (3, 1, 3, 1, 200), # active
    (4, 2, 3, 1, 100), # active
    (5, 4, 3, 1, 100), # active
    (6, 5, 3, 1, 100), # active
    (7, 1, 2, 1, 100),
    (8, 1, 2, 0, 200), # dead edge
    (9, 2, 4, 1, 100)  # active
]
c.executemany("INSERT INTO citations VALUES (?, ?, ?, ?, ?)", citations)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
