#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    python3 -c "
import sqlite3
import json
import os

db_path = '/home/user/research_data.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT, properties TEXT)''')
c.execute('''CREATE TABLE edges (source INTEGER, target INTEGER, type TEXT)''')

authors = {
    1: 'Dr. Alice', 2: 'Dr. Bob', 3: 'Dr. Charlie', 4: 'Dr. Diana',
    5: 'Dr. Eve', 6: 'Dr. Frank', 7: 'Dr. Grace'
}
for aid, name in authors.items():
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (aid, 'Author', json.dumps({'name': name})))

papers = {
    10: 'P1', 11: 'P2', 12: 'P3', 13: 'P4',
    14: 'P5', 15: 'P6', 16: 'P7'
}
for pid, title in papers.items():
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (pid, 'Paper', json.dumps({'title': title})))

wrote_edges = [
    (1, 10), (2, 11), (3, 12), (4, 13),
    (5, 14), (6, 15), (7, 16)
]
for src, tgt in wrote_edges:
    c.execute(\"INSERT INTO edges VALUES (?, ?, 'WROTE')\", (src, tgt))

cites_edges = [
    (11, 10), (12, 10), (13, 10), (11, 12),
    (14, 15), (15, 16)
]
for src, tgt in cites_edges:
    c.execute(\"INSERT INTO edges VALUES (?, ?, 'CITES')\", (src, tgt))

conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
