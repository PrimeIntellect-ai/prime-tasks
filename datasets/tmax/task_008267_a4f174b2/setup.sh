#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/data.db')
c = conn.cursor()
c.execute('CREATE TABLE communications(sender INT, receiver INT, time INT)')
c.execute('CREATE INDEX idx_time ON communications(time)')

edges = [
    # Valid cycle 1
    (1, 2, 100),
    (2, 3, 110),
    (3, 1, 120),

    # Invalid cycle (times not increasing)
    (4, 5, 200),
    (5, 6, 190),
    (6, 4, 210),

    # Valid cycle 2
    (7, 8, 300),
    (8, 9, 310),
    (9, 7, 320),

    # Valid cycle 3
    (10, 11, 400),
    (11, 12, 410),
    (12, 10, 420),

    # Extra noise
    (2, 1, 50),
    (3, 4, 150)
]

c.executemany('INSERT INTO communications VALUES (?,?,?)', edges)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
