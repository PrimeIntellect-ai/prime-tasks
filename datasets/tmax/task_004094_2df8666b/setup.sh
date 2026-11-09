#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT, properties TEXT)''')
cursor.execute('''CREATE TABLE edges (source TEXT, target TEXT, rel_type TEXT)''')

# Insert nodes
nodes = [
    ('P_Alice', 'Person', '{}'),
    ('P_Bob', 'Person', '{}'),
    ('P_Charlie', 'Person', '{}'),
    ('P_David', 'Person', '{}'),
    ('P_Eve', 'Person', '{}'),
    ('P_Frank', 'Person', '{}'),
    ('P_Grace', 'Person', '{}'),
    ('P_Heidi', 'Person', '{}'),
    ('C_ValidCorp', 'Company', '{}')
]
cursor.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)

# Insert edges
edges = [
    # Valid edges
    ('P_Alice', 'C_ValidCorp', 'WORKS_FOR'),
    ('P_Bob', 'P_Alice', 'KNOWS'),

    # Stale WORKS_FOR edges (Target missing)
    ('P_Charlie', 'C_DeletedCorp1', 'WORKS_FOR'),
    ('P_David', 'C_DeletedCorp2', 'WORKS_FOR'),
    ('P_Eve', 'C_DeletedCorp1', 'WORKS_FOR'),
    ('P_Frank', 'C_DeletedCorp2', 'WORKS_FOR'),
    ('P_Grace', 'C_DeletedCorp1', 'WORKS_FOR'),
    ('P_Heidi', 'C_DeletedCorp2', 'WORKS_FOR'),

    # Other stale edges (Source missing)
    ('MissingPerson1', 'P_Alice', 'KNOWS'),
    ('MissingPerson2', 'C_ValidCorp', 'WORKS_FOR'),

    # Other stale edges (Target missing, not WORKS_FOR)
    ('P_Bob', 'MissingPerson3', 'KNOWS')
]
cursor.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
