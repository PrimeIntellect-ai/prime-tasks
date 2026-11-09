#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/research_data.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)")
c.execute("CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER)")
c.execute("CREATE TABLE citations (citing_paper_id INTEGER, cited_paper_id INTEGER)")

papers = [
    (1, "Deep Learning", 2015),
    (2, "Adam Optimizer", 2014),
    (3, "ResNet", 2016),
    (4, "Transformers", 2017),
    (5, "BERT", 2018),
    (6, "Old Paper", 2009),
    (7, "GPT", 2018),
    (8, "Vision Transformers", 2021)
]
c.executemany("INSERT INTO papers VALUES (?, ?, ?)", papers)

authors = [
    (1, "Hinton"),
    (2, "Kingma"),
    (3, "Ba"),
    (4, "He"),
    (5, "Vaswani"),
    (6, "Devlin"),
    (7, "Smith"),
    (8, "Dosovitskiy")
]
c.executemany("INSERT INTO authors VALUES (?, ?)", authors)

paper_authors = [
    (1, 1),
    (2, 2), (2, 3),
    (3, 4),
    (4, 5),
    (5, 6),
    (6, 7),
    (7, 5),
    (8, 8)
]
c.executemany("INSERT INTO paper_authors VALUES (?, ?)", paper_authors)

citations = [
    (5, 4),
    (4, 3),
    (4, 7),
    (7, 4),
    (4, 1),
    (3, 6),
    (8, 3),
    (3, 1)
]
c.executemany("INSERT INTO citations VALUES (?, ?)", citations)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
