#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Create the SQLite DB
db_path = '/home/user/backups.sqlite'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE backups (service_id TEXT PRIMARY KEY, status TEXT, last_backup_time TEXT)')

backups_data = [
    ('Web', 'FAILED', '2023-10-01T10:00:00Z'),
    ('API', 'SUCCESS', '2023-10-01T10:00:00Z'),
    ('Auth', 'FAILED', '2023-10-01T10:00:00Z'),
    ('DB', 'FAILED', '2023-10-01T10:00:00Z'),
    ('Cache', 'FAILED', '2023-10-01T10:00:00Z'),
    ('Worker', 'SUCCESS', '2023-10-01T10:00:00Z'),
    ('Search', 'FAILED', '2023-10-01T10:00:00Z')
]
c.executemany('INSERT INTO backups VALUES (?, ?, ?)', backups_data)
conn.commit()
conn.close()

# 2. Create the JSON file
services_data = [
    {"service_id": "Web", "depends_on": ["API", "Auth"]},
    {"service_id": "API", "depends_on": ["DB", "Cache"]},
    {"service_id": "Auth", "depends_on": ["DB"]},
    {"service_id": "Worker", "depends_on": ["DB", "Cache"]},
    {"service_id": "Search", "depends_on": ["DB", "Worker"]},
    {"service_id": "DB", "depends_on": []},
    {"service_id": "Cache", "depends_on": []}
]

with open('/home/user/services.json', 'w') as f:
    json.dump(services_data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
