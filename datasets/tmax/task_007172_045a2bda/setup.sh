#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/service_backup.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Create obfuscated table names
cur.execute('''
CREATE TABLE tbl_entity_registry (
    ent_id INTEGER PRIMARY KEY,
    ent_identifier TEXT NOT NULL UNIQUE
)
''')

cur.execute('''
CREATE TABLE tbl_entity_links (
    link_id INTEGER PRIMARY KEY,
    parent_ent_id INTEGER,
    child_ent_id INTEGER,
    FOREIGN KEY(parent_ent_id) REFERENCES tbl_entity_registry(ent_id),
    FOREIGN KEY(child_ent_id) REFERENCES tbl_entity_registry(ent_id)
)
''')

# Create a secondary index that the user is instructed to drop
cur.execute('CREATE INDEX idx_stale_parent_link ON tbl_entity_links(parent_ent_id)')

# Populate data
entities = [
    (1, 'gateway-svc'),
    (2, 'auth-svc'),
    (3, 'user-db'),
    (4, 'payment-svc'),
    (5, 'payment-db'),
    (6, 'cache-node-1'),
    (7, 'cache-node-2'),
    (8, 'worker-queue')
]

links = [
    (1, 1, 2), # gateway -> auth
    (2, 1, 4), # gateway -> payment
    (3, 2, 3), # auth -> user-db
    (4, 4, 5), # payment -> payment-db
    (5, 2, 6), # auth -> cache 1
    (6, 2, 7), # auth -> cache 2
    (7, 4, 8)  # payment -> worker
]

cur.executemany('INSERT INTO tbl_entity_registry VALUES (?, ?)', entities)
cur.executemany('INSERT INTO tbl_entity_links VALUES (?, ?, ?)', links)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
