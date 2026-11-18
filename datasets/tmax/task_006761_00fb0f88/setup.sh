#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
conn = sqlite3.connect('/home/user/graph.db')
c = conn.cursor()

c.execute('''CREATE TABLE Nodes (id TEXT PRIMARY KEY, type TEXT)''')
c.execute('''CREATE TABLE Edges (source_id TEXT, target_id TEXT, relation_type TEXT)''')

nodes = [
    ('S1', 'Service'), ('S2', 'Service'), ('S3', 'Service'),
    ('D1', 'Database'), ('D2', 'Database'),
    ('Q1', 'Queue'), ('A1', 'API'), ('A2', 'API')
]
c.executemany('INSERT INTO Nodes VALUES (?, ?)', nodes)

edges = [
    ('S1', 'S2', 'depends_on'),
    ('S2', 'D1', 'depends_on'),
    ('S2', 'Q1', 'depends_on'),
    ('Q1', 'D2', 'depends_on'), 
    ('S3', 'A1', 'depends_on'),
    ('A1', 'A2', 'depends_on'),
    ('A2', 'D2', 'depends_on'), 
    ('S1', 'A1', 'communicates_with') 
]
c.executemany('INSERT INTO Edges VALUES (?, ?, ?)', edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
