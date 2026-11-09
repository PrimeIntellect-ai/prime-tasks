#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import os
import sqlite3

db_path = '/home/user/research.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT)')
c.execute('CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER, FOREIGN KEY(paper_id) REFERENCES papers(id), FOREIGN KEY(author_id) REFERENCES authors(id))')

authors = [
    (1, 'Alice Smith'),
    (2, 'Bob Jones'),
    (3, 'Charlie Brown'),
    (4, 'David Miller'),
    (5, 'Eve Davis'),
    (6, 'Frank Wilson')
]

papers = [
    (1, 'Deep Learning for Graphs'),
    (2, 'Relational Database Optimization'),
    (3, 'Knowledge Graph Embeddings'),
    (4, 'NoSQL vs SQL')
]

paper_authors = [
    (1, 1), (1, 2), (1, 3),
    (2, 1), (2, 4),
    (3, 1), (3, 5), (3, 6),
    (4, 2), (4, 4)
]

c.executemany('INSERT INTO authors VALUES (?, ?)', authors)
c.executemany('INSERT INTO papers VALUES (?, ?)', papers)
c.executemany('INSERT INTO paper_authors VALUES (?, ?)', paper_authors)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
