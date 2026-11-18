#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/network.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE entities (id TEXT PRIMARY KEY, type TEXT, region TEXT)")
c.execute("CREATE TABLE transfers (source_id TEXT, target_id TEXT, amount REAL, timestamp INTEGER)")

entities = [
    ('E1', 'Bank', 'North'),
    ('E2', 'Corp', 'North'),
    ('E3', 'Retail', 'South'),
    ('E4', 'Corp', 'South'),
    ('E5', 'Bank', 'East'),
    ('E6', 'Retail', 'East'),
    ('E7', 'Corp', 'West')
]

transfers = [
    ('E1', 'E2', 100.0, 1),
    ('E2', 'E3', 50.0, 2),
    ('E3', 'E4', 200.0, 3),
    ('E1', 'E5', 300.0, 4),
    ('E5', 'E6', 150.0, 5),
    ('E7', 'E2', 400.0, 6)
]

c.executemany("INSERT INTO entities VALUES (?, ?, ?)", entities)
c.executemany("INSERT INTO transfers VALUES (?, ?, ?, ?)", transfers)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
