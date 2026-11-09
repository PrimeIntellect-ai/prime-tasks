#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = '/home/user/backups.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT)''')
c.execute('''CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, timestamp INTEGER, size_bytes INTEGER, status TEXT)''')

c.execute("INSERT INTO servers (id, hostname) VALUES (1, 'db-prod-01')")
c.execute("INSERT INTO servers (id, hostname) VALUES (2, 'web-prod-01')")

# Insert backups for db-prod-01
c.execute("INSERT INTO backups (server_id, timestamp, size_bytes, status) VALUES (1, 1000, 500, 'SUCCESS')")
c.execute("INSERT INTO backups (server_id, timestamp, size_bytes, status) VALUES (1, 1001, 200, 'FAILED')")
c.execute("INSERT INTO backups (server_id, timestamp, size_bytes, status) VALUES (1, 1002, 300, 'SUCCESS')")

# Insert backups for web-prod-01
c.execute("INSERT INTO backups (server_id, timestamp, size_bytes, status) VALUES (2, 1000, 1000, 'SUCCESS')")

conn.commit()
conn.close()

graph = [
    {"backup_id": 1, "depends_on": [], "restore_time_minutes": 10},
    {"backup_id": 2, "depends_on": [1], "restore_time_minutes": 5},
    {"backup_id": 3, "depends_on": [1], "restore_time_minutes": 15},
    {"backup_id": 4, "depends_on": [2, 3], "restore_time_minutes": 5},
    {"backup_id": 50, "depends_on": [4], "restore_time_minutes": 20}
]

with open('/home/user/dependency_graph.json', 'w') as f:
    json.dump(graph, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
