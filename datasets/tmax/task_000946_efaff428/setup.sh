#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('research_data.sqlite')
c = conn.cursor()

c.execute('''
CREATE TABLE authors (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
)
''')

c.execute('''
CREATE TABLE papers (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    year INTEGER NOT NULL
)
''')

c.execute('''
CREATE TABLE paper_authors (
    paper_id INTEGER,
    author_id INTEGER,
    FOREIGN KEY(paper_id) REFERENCES papers(id),
    FOREIGN KEY(author_id) REFERENCES authors(id)
)
''')

c.execute('''
CREATE TABLE citations (
    citing_paper_id INTEGER,
    cited_paper_id INTEGER,
    FOREIGN KEY(citing_paper_id) REFERENCES papers(id),
    FOREIGN KEY(cited_paper_id) REFERENCES papers(id)
)
''')

authors = [(1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana'), (5, 'Eve')]
c.executemany('INSERT INTO authors VALUES (?, ?)', authors)

papers = [
    (10, 'Paper A', 2020),
    (11, 'Paper B', 2020),
    (12, 'Paper C', 2020),
    (13, 'Paper D', 2021),
    (14, 'Paper E', 2021),
    (15, 'Paper F', 2022)
]
c.executemany('INSERT INTO papers VALUES (?, ?, ?)', papers)

paper_authors = [
    (10, 1), (10, 2),
    (11, 2), (11, 3),
    (12, 4),
    (13, 1), (13, 5),
    (14, 3),
    (15, 2), (15, 4)
]
c.executemany('INSERT INTO paper_authors VALUES (?, ?)', paper_authors)

citations = [
    (10, 11),
    (11, 13),
    (13, 15),
    (10, 12),
    (14, 11),
    (15, 12),
    (15, 11)
]
c.executemany('INSERT INTO citations VALUES (?, ?)', citations)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    chmod -R 777 /home/user
