#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 << 'EOF'
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/research_data.db'
jsonl_path = '/home/user/metadata.jsonl'

# 1. Create SQLite DB
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE subjects (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE measurements (id INTEGER PRIMARY KEY, subject_id INTEGER, timestamp DATETIME, value REAL)''')
c.execute('''CREATE TABLE latest_measurements_cache (subject_id INTEGER, latest_timestamp DATETIME, value REAL)''')

subjects = [(1, 'Alpha'), (2, 'Beta'), (3, 'Gamma'), (4, 'Delta')]
c.executemany('INSERT INTO subjects VALUES (?, ?)', subjects)

# True measurements
measurements = [
    (1, 1, '2023-01-01 10:00:00', 10.5),
    (2, 1, '2023-01-02 10:00:00', 12.0), # Latest for 1
    (3, 2, '2023-01-01 11:00:00', 8.2),  # Latest for 2
    (4, 3, '2023-01-01 09:00:00', 15.1),
    (5, 3, '2023-01-03 09:00:00', 14.8), # Latest for 3
]
c.executemany('INSERT INTO measurements VALUES (?, ?, ?, ?)', measurements)

# Stale cache
stale_cache = [
    (1, '2023-01-01 10:00:00', 10.5), # Out of date
    (2, '2023-01-01 11:00:00', 8.2),
    (3, '2023-01-01 09:00:00', 15.1), # Out of date
    (4, '2023-01-01 00:00:00', 99.9)  # Fake/Corrupted
]
c.executemany('INSERT INTO latest_measurements_cache VALUES (?, ?, ?)', stale_cache)

conn.commit()
conn.close()

# 2. Create JSONL
metadata = [
    {"subject_id": 1, "attributes": {"type": "control", "age": 30}, "related_subjects": [2, 3]},
    {"subject_id": 2, "attributes": {"type": "treatment", "age": 25}, "related_subjects": [3]},
    {"subject_id": 3, "attributes": {"type": "treatment", "age": 28}, "related_subjects": [4, 99]},
    {"subject_id": 4, "attributes": {"type": "control", "age": 40}, "related_subjects": [1]}
]

with open(jsonl_path, 'w') as f:
    for m in metadata:
        f.write(json.dumps(m) + '\n')
EOF

    chmod -R 777 /home/user
