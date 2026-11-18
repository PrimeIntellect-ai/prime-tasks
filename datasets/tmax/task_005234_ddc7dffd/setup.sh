#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/network.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''
CREATE TABLE nodes (
    node_id INTEGER PRIMARY KEY,
    hostname TEXT NOT NULL UNIQUE,
    device_type TEXT
)
''')

cursor.execute('''
CREATE TABLE links (
    link_id INTEGER PRIMARY KEY,
    src_node_id INTEGER,
    dst_node_id INTEGER,
    latency INTEGER,
    FOREIGN KEY(src_node_id) REFERENCES nodes(node_id),
    FOREIGN KEY(dst_node_id) REFERENCES nodes(node_id)
)
''')

# Insert nodes
nodes = [
    (1, 'gateway-alpha', 'gateway'),
    (2, 'router-b', 'router'),
    (3, 'router-c', 'router'),
    (4, 'switch-d', 'switch'),
    (5, 'storage-omega', 'server'),
    (6, 'firewall-x', 'firewall')
]
cursor.executemany('INSERT INTO nodes VALUES (?, ?, ?)', nodes)

# Insert edges (directed)
links = [
    (1, 1, 2, 10),  
    (2, 1, 3, 50),  
    (3, 2, 4, 20),  
    (4, 3, 4, 5),   
    (5, 3, 5, 100), 
    (6, 4, 5, 15),  
    (7, 2, 6, 5),   
    (8, 6, 5, 60)   
]
cursor.executemany('INSERT INTO links VALUES (?, ?, ?, ?)', links)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
