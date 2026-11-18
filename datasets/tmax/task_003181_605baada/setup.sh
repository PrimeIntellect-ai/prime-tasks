#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/access_graph.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    type TEXT,
    name TEXT
)
''')

cursor.execute('''
CREATE TABLE relations (
    source_id INTEGER,
    target_id INTEGER,
    FOREIGN KEY(source_id) REFERENCES entities(id),
    FOREIGN KEY(target_id) REFERENCES entities(id)
)
''')

entities = [
    (1, 'User', 'Alice'),
    (2, 'User', 'Bob'),
    (3, 'Group', 'Devs'),
    (4, 'Group', 'Admins'),
    (5, 'System', 'Prod-DB'),
    (6, 'System', 'Staging-DB'),
    (7, 'System', 'CI-Server'),
    (8, 'System', 'Analytics'),
    (9, 'System', 'Vault'),
    (10, 'System', 'Legacy'),
    (11, 'System', 'Web-Server'),
    (12, 'System', 'App-Server'),
    (13, 'System', 'Cache'),
    (14, 'System', 'Queue')
]
cursor.executemany("INSERT INTO entities VALUES (?, ?, ?)", entities)

relations = [
    (1, 3),
    (2, 4),
    (4, 3),
    (3, 6),
    (3, 7),
    (3, 11),
    (3, 12),
    (3, 13),
    (3, 14),
    (4, 5),
    (4, 9),
    (1, 8),
]
cursor.executemany("INSERT INTO relations VALUES (?, ?)", relations)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
