#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/manufacturing.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE components (
    id INTEGER PRIMARY KEY,
    name TEXT
)
''')

cursor.execute('''
CREATE TABLE bom (
    parent_id INTEGER,
    child_id INTEGER,
    quantity INTEGER,
    PRIMARY KEY (parent_id, child_id)
)
''')

components = [
    (1, 'Final Product'),
    (2, 'Sub-Assembly A'),
    (3, 'Sub-Assembly B'),
    (4, 'Part C'),
    (5, 'Part D'),
    (6, 'Standard Screw')
]
cursor.executemany('INSERT INTO components VALUES (?, ?)', components)

bom = [
    (1, 2, 2),
    (1, 3, 1),
    (2, 4, 3),
    (2, 5, 4),
    (3, 5, 2),
    (3, 6, 10),
    (4, 6, 2),
    (5, 6, 4)
]
cursor.executemany('INSERT INTO bom VALUES (?, ?, ?)', bom)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
