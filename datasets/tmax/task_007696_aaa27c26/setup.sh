#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()

c.execute('''CREATE TABLE papers (paper_id INTEGER PRIMARY KEY, title TEXT)''')
c.execute('''CREATE TABLE authors (author_id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER,
             FOREIGN KEY(paper_id) REFERENCES papers(paper_id),
             FOREIGN KEY(author_id) REFERENCES authors(author_id))''')

authors = [
    (1, "Alice Smith"),
    (2, "Bob Jones"),
    (3, "Charlie Brown"),
    (4, "David Clark"),
    (5, "Eve Davis"),
    (6, "Frank White")
]
c.executemany("INSERT INTO authors VALUES (?, ?)", authors)

papers = [
    (101, "Quantum AI"),
    (102, "Neural Networks"),
    (103, "Graph Databases")
]
c.executemany("INSERT INTO papers VALUES (?, ?)", papers)

relations = [
    (101, 1), (101, 2), (101, 3),
    (102, 1), (102, 4), (102, 5),
    (103, 2), (103, 6)
]
c.executemany("INSERT INTO paper_authors VALUES (?, ?)", relations)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
