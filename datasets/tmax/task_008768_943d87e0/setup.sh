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

c.execute('CREATE TABLE entities (id INTEGER PRIMARY KEY, entity_type TEXT)')
c.execute('CREATE TABLE relations (src INTEGER, dst INTEGER, weight REAL, timestamp INTEGER)')
c.execute('CREATE INDEX idx_rel_src ON relations(src)')

entities = [
    (1, 'Protein'),
    (2, 'Protein'),
    (3, 'Gene'),
    (4, 'Gene'),
    (5, 'Metabolite')
]
c.executemany('INSERT INTO entities VALUES (?, ?)', entities)

# 7 rows to match the test requirements
relations = [
    (1, 3, 5.0, 200),
    (2, 4, 15.0, 150),
    (3, 5, 50.0, 100),
    (3, 5, 20.0, 300),
    (4, 1, 8.0, 100),
    (5, 2, 30.0, 100),
    (5, 1, 2.0, 400),
]
c.executemany('INSERT INTO relations VALUES (?, ?, ?, ?)', relations)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
