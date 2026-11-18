#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json
import os

db_path = "/home/user/company.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''
CREATE TABLE personnel (
    id INTEGER PRIMARY KEY,
    reports_to INTEGER,
    document TEXT
)
''')

data = [
    (1, None, json.dumps({"compensation": {"base": 100.0, "bonus": 50.0}, "role": "CEO"})),
    (2, 1, json.dumps({"compensation": {"base": 80.0, "bonus": 20.0}, "role": "VP"})),
    (3, 1, json.dumps({"compensation": {"base": 90.0}, "role": "VP"})),
    (4, 2, json.dumps({"compensation": {"base": 50.0, "bonus": 5.0}, "role": "IC"})),
    (5, 2, json.dumps({"compensation": {"bonus": 10.0}, "role": "IC"})),
    (6, 3, json.dumps({"compensation": {"base": 60.0, "bonus": 10.0}, "role": "IC"}))
]

c.executemany('INSERT INTO personnel VALUES (?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
