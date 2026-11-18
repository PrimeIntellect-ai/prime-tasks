#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backup.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE sensor_data (id INTEGER PRIMARY KEY, sensor_id INTEGER, epoch_time INTEGER, reading REAL)')

data = [
    (1, 101, 1000, 25.0),
    (2, 101, 1005, 26.5),
    (3, 101, 1005, 26.1),
    (4, 102, 1000, 15.0),
    (5, 101, 1010, 27.0),
    (6, 102, 1005, 14.5),
    (7, 102, 1010, 14.0),
    (8, 102, 1010, 14.8),
    (9, 103, 2000, 10.0),
    (10, 103, 2005, 12.0),
    (11, 103, 2005, 12.5),
    (12, 103, 2010, 11.0)
]
c.executemany('INSERT INTO sensor_data VALUES (?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
