#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/telemetry.db')
c = conn.cursor()

c.execute('''
CREATE TABLE signals (
    id INTEGER PRIMARY KEY,
    source TEXT,
    destination TEXT,
    power REAL,
    timestamp INTEGER
)
''')

# Create an index
c.execute('CREATE INDEX idx_ts ON signals(timestamp)')

events = [
    # Valid A -> B -> C (power = 60.0)
    (1, 'NodeA', 'NodeB', 60.5, 1000),
    (2, 'NodeB', 'NodeC', 80.0, 1050),

    # Invalid: time difference > 100
    (3, 'NodeX', 'NodeY', 90.0, 2000),
    (4, 'NodeY', 'NodeZ', 85.0, 2150),

    # Invalid: power <= 50
    (5, 'NodeM', 'NodeN', 40.0, 3000),
    (6, 'NodeN', 'NodeO', 95.0, 3050),

    # Valid P -> Q -> R (power = 75.0)
    (7, 'NodeP', 'NodeQ', 80.0, 4000),
    (8, 'NodeQ', 'NodeR', 75.0, 4080),

    # Valid NodeB -> NodeC -> NodeD (power = 70.0)
    (9, 'NodeC', 'NodeD', 70.0, 1100)
]

c.executemany('INSERT INTO signals VALUES (?, ?, ?, ?, ?)', events)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
