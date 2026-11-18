#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/graph.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE nodes (id TEXT, label TEXT)')
c.execute('CREATE TABLE edges (source TEXT, target TEXT, cost REAL)')

nodes = [
    ('S1', 'Supplier'),
    ('S2', 'Supplier'),
    ('M1', 'Manufacturer'),
    ('M2', 'Manufacturer'),
    ('M3', 'Manufacturer'),
    ('R1', 'Retailer'),
    ('R2', 'Retailer'),
    ('X1', 'Supplier'),
    ('X2', 'Distributor')
]

edges = [
    ('S1', 'M1', 5.0),
    ('S2', 'M1', 3.0),
    ('M1', 'R1', 4.0),
    ('M1', 'R2', 8.0),
    ('S1', 'M2', 10.0),
    ('M2', 'R2', 2.0),
    ('S2', 'M3', 6.0),
    ('M3', 'X2', 1.0),
    ('X1', 'X2', 4.0)
]

c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
c.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
