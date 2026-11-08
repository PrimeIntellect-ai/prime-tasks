#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json

db_path = "/home/user/backup_catalog.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE jobs (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    size_bytes INTEGER,
    status TEXT,
    start_time TIMESTAMP
)
''')

cursor.execute('''
CREATE TABLE configs (
    job_id INTEGER PRIMARY KEY,
    settings TEXT
)
''')

# Insert data
# Roots
roots = [
    (1, None, 1000, "SUCCESS"), # long_term
    (10, None, 500, "SUCCESS"), # short_term
    (20, None, 2000, "SUCCESS"), # long_term
    (30, None, 3000, "SUCCESS"), # long_term
    (40, None, 1500, "SUCCESS"), # long_term
    (50, None, 2500, "SUCCESS")  # long_term
]
cursor.executemany("INSERT INTO jobs (id, parent_id, size_bytes, status) VALUES (?, ?, ?, ?)", roots)

# Incrementals (10 to match the test assertion)
incrementals = [
    # Chain 1 (root 1): + 100 + 150 + 50 = 300. Total = 1300. num=3. avg=100.00
    (2, 1, 100, "SUCCESS"),
    (3, 2, 150, "SUCCESS"),
    (4, 3, 50, "SUCCESS"),
    # Chain 20 (root 20): + 500 + 600 = 1100. Total = 3100. num=2. avg=550.00
    (21, 20, 500, "SUCCESS"),
    (22, 21, 600, "SUCCESS"),
    # Chain 30 (root 30): + 100 = 100. Total = 3100. num=1. avg=100.00
    (31, 30, 100, "SUCCESS"),
    # Chain 40 (root 40): Total = 1500. num=0. avg=0.00
    # Chain 50 (root 50): + 100 + 100 + 100 + 100 = 400. Total = 2900. num=4. avg=100.00
    (51, 50, 100, "SUCCESS"),
    (52, 51, 100, "SUCCESS"),
    (53, 52, 100, "SUCCESS"),
    (54, 50, 100, "SUCCESS"), # branch off root
]
cursor.executemany("INSERT INTO jobs (id, parent_id, size_bytes, status) VALUES (?, ?, ?, ?)", incrementals)

# Configs
configs = [
    (1, json.dumps({"retention_policy": "long_term", "region": "us-east"})),
    (10, json.dumps({"retention_policy": "short_term", "region": "us-west"})),
    (20, json.dumps({"retention_policy": "long_term", "region": "us-east"})),
    (30, json.dumps({"retention_policy": "long_term", "region": "eu-central"})),
    (40, json.dumps({"retention_policy": "long_term", "region": "us-east"})),
    (50, json.dumps({"retention_policy": "long_term", "region": "us-west"})),
]
cursor.executemany("INSERT INTO configs (job_id, settings) VALUES (?, ?)", configs)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
