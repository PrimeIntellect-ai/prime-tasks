#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/network_staging.db')
cursor = conn.cursor()

# Create table
cursor.execute('''
CREATE TABLE etl_edges_v2 (
    id INTEGER PRIMARY KEY,
    src_node INTEGER,
    dst_node INTEGER,
    weight REAL,
    status TEXT
)
''')

# Insert data
edges = [
    (1, 100, 200, 1.0, 'ACTIVE'),
    (2, 100, 201, 1.5, 'ACTIVE'),
    (3, 100, 202, 0.5, 'INACTIVE'),
    (4, 101, 200, 2.0, 'ACTIVE'),
    (5, 101, 203, 1.0, 'ACTIVE'),
    (6, 101, 204, 1.0, 'ACTIVE'),
    (7, 102, 100, 1.0, 'ACTIVE'),
    (8, 102, 101, 1.0, 'ACTIVE'),
    (9, 103, 300, 1.0, 'INACTIVE'),
    (10, 104, 301, 1.0, 'ACTIVE'),
    (11, 104, 302, 1.0, 'ACTIVE'),
    (12, 104, 303, 1.0, 'ACTIVE'),
    (13, 104, 304, 1.0, 'ACTIVE')
]

cursor.executemany('INSERT INTO etl_edges_v2 VALUES (?, ?, ?, ?, ?)', edges)
conn.commit()

# Create the index that the user is supposed to bypass or drop
cursor.execute('CREATE INDEX idx_src_node_corrupt ON etl_edges_v2(src_node)')
conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    cat << 'EOF' > /home/user/.expected_out_degree.csv
node_id,out_degree
104,4
101,3
100,2
102,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
