#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/knowledge_graph.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)''')
cur.execute('''CREATE TABLE citations (source INTEGER, target INTEGER)''')

papers = [
    (1, "Paper 1", 2005),
    (2, "Paper 2", 2008),
    (3, "Paper 3", 2009),
    (4, "Paper 4", 2005),
    (5, "Paper 5", 2006),
    (6, "Paper 6", 2007),
    (10, "Paper 10", 2011),
    (11, "Paper 11", 2012),
    (12, "Paper 12", 2013),
    (20, "Paper 20", 2015),
    (21, "Paper 21", 2016),
    (22, "Paper 22", 2017),
    (30, "Paper 30", 2018),
    (31, "Paper 31", 2019),
    (32, "Paper 32", 2020),
    (40, "Paper 40", 2012),
    (41, "Paper 41", 2012),
    (42, "Paper 42", 2012),
    (50, "Paper 50", 2018)
]

citations = [
    (4, 5), (5, 6), (4, 6),
    (10, 11), (11, 12), (10, 12),
    (20, 21), (21, 22), (20, 22),
    (30, 31), (31, 32), (30, 32),
    (40, 10), (41, 10), (42, 10),
    (40, 11), (41, 11),
    (50, 30)
]

cur.executemany("INSERT INTO papers VALUES (?, ?, ?)", papers)
cur.executemany("INSERT INTO citations VALUES (?, ?)", citations)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
