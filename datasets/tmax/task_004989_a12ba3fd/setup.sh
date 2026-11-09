#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os
import random
from datetime import datetime, timedelta

db_path = "/home/user/backups_meta.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''
    CREATE TABLE servers (
        id INTEGER PRIMARY KEY,
        hostname TEXT,
        region TEXT
    )
''')

cur.execute('''
    CREATE TABLE backups (
        id INTEGER PRIMARY KEY,
        server_id INTEGER,
        timestamp TEXT,
        size_bytes INTEGER,
        status TEXT
    )
''')

# Deterministic seed
random.seed(42)

servers = [
    (1, "app-server-eu", "eu-west-1"),
    (2, "db-server-us", "us-east-1"),
    (3, "cache-server-ap", "ap-south-1")
]

cur.executemany("INSERT INTO servers VALUES (?, ?, ?)", servers)

start_time = datetime(2023, 10, 1)
backups = []
b_id = 1

for s_id, hostname, region in servers:
    current_time = start_time
    for i in range(20):
        # 90% success rate
        status = "SUCCESS" if random.random() < 0.9 else "FAILED"
        # Sizes between 20MB and 100MB
        size = random.randint(20000000, 100000000)

        backups.append((b_id, s_id, current_time.isoformat() + "Z", size, status))
        b_id += 1
        current_time += timedelta(hours=12)

# Scramble the insert order to simulate real-world unclustered inserts
random.shuffle(backups)
cur.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", backups)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
