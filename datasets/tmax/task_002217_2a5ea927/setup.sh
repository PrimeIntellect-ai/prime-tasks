#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/network.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)')
c.execute('CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER, FOREIGN KEY(paper_id) REFERENCES papers(id), FOREIGN KEY(author_id) REFERENCES authors(id))')

# Insert authors
authors = [
    (1, "Alice Smith"),
    (2, "Charlie Brown"),
    (3, "David Lee"),
    (4, "Bob Jones"),
    (5, "Eve Davis")
]
c.executemany('INSERT INTO authors VALUES (?, ?)', authors)

# Insert papers
papers = [
    (101, "Paper A", 2020),
    (102, "Paper B", 2021),
    (103, "Paper C", 2019),
    (104, "Paper D", 2022),
    (105, "Paper E", 2023),
    (106, "Paper F", 2021)
]
c.executemany('INSERT INTO papers VALUES (?, ?, ?)', papers)

# Insert paper_authors (defining the graph)
paper_authors = [
    (101, 1), (101, 2), # Alice & Charlie (co-authors)
    (102, 2), (102, 3), # Charlie & David (co-authors)
    (103, 3), (103, 4), # David & Bob (co-authors)
    (104, 1), (104, 5), # Alice & Eve (co-authors)
    (105, 1),           # Alice solo
    (106, 3)            # David solo
]
c.executemany('INSERT INTO paper_authors VALUES (?, ?)', paper_authors)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
