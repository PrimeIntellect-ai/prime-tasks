#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/etl_source.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE events (
    id INTEGER PRIMARY KEY, 
    src_node TEXT, 
    dst_node TEXT, 
    event_time TIMESTAMP, 
    status TEXT
)
''')

# Insert data
events = [
    (1, 'A', 'B', '2023-01-01 10:00:00', 'SUCCESS'),
    (2, 'A', 'B', '2023-01-01 11:00:00', 'FAILED'),
    (3, 'A', 'C', '2023-01-01 10:30:00', 'SUCCESS'),
    (4, 'B', 'C', '2023-01-01 10:00:00', 'SUCCESS'),
    (5, 'B', 'C', '2023-01-02 10:00:00', 'SUCCESS'),
    (6, 'C', 'A', '2023-01-01 12:00:00', 'FAILED'),
    (7, 'D', 'A', '2023-01-01 10:00:00', 'SUCCESS'),
    (8, 'D', 'B', '2023-01-01 10:00:00', 'SUCCESS'),
    (9, 'A', 'D', '2023-01-01 10:00:00', 'SUCCESS')
]

c.executemany('INSERT INTO events VALUES (?, ?, ?, ?, ?)', events)
c.execute('CREATE INDEX idx_stale_data ON events (status, event_time)')
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
