#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()
c.execute('CREATE TABLE backups (id INTEGER PRIMARY KEY, parent_id INTEGER, status TEXT, timestamp INTEGER)')
c.execute('CREATE INDEX idx_status_time ON backups(status, timestamp)')

# Data definition
data = [
    # Chain 1: Success (Root TS 100)
    (1, None, 'SUCCESS', 100),
    (2, 1, 'SUCCESS', 110),
    (3, 2, 'SUCCESS', 120),

    # Chain 2: Failed (Root TS 200) -> 4,5,6
    (4, None, 'SUCCESS', 200),
    (5, 4, 'FAILED', 210),
    (6, 5, 'SUCCESS', 220),

    # Chain 3: Failed (Root TS 300) -> 7,8,9
    (7, None, 'SUCCESS', 300),
    (8, 7, 'SUCCESS', 310),
    (9, 8, 'FAILED', 320),

    # Chain 4: Success (Root TS 400)
    (10, None, 'SUCCESS', 400),
    (11, 10, 'SUCCESS', 410),

    # Chain 5: Failed (Root TS 500) -> 12,13,14
    (12, None, 'FAILED', 500),
    (13, 12, 'SUCCESS', 510),
    (14, 13, 'SUCCESS', 520),

    # Chain 6: Failed (Root TS 600) -> 15,16
    (15, None, 'SUCCESS', 600),
    (16, 15, 'FAILED', 610)
]

c.executemany('INSERT INTO backups VALUES (?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
