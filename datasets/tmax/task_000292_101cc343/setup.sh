#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/research.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, institution TEXT)''')
c.execute('''CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, citations INTEGER)''')
c.execute('''CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER, PRIMARY KEY (paper_id, author_id))''')

authors = [
    (1, 'Alice Smith', 'MIT'),
    (2, 'Bob Jones', 'Stanford'),
    (3, 'Charlie Brown', 'MIT'),
    (4, 'Diana Prince', 'Oxford'),
    (5, 'Evan Wright', 'Stanford')
]
c.executemany("INSERT INTO authors VALUES (?,?,?)", authors)

papers = [
    (101, 'Deep Learning Basics', 2018, 50),
    (102, 'Advanced Graph NNs', 2020, 10),
    (103, 'Transformers', 2021, 100),
    (104, 'Quantum Computing', 2019, 75),
    (105, 'Survey of AI', 2022, 5)
]
c.executemany("INSERT INTO papers VALUES (?,?,?,?)", papers)

paper_authors = [
    (101, 1), (101, 2),
    (102, 2), (102, 3),
    (103, 1), (103, 2), (103, 3),
    (104, 4), (104, 5),
    (105, 1), (105, 5)
]
c.executemany("INSERT INTO paper_authors VALUES (?,?)", paper_authors)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
