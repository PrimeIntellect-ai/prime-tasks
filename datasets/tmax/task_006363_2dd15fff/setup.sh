#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Create SQLite DB
db_path = '/home/user/sensors.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE readings (timestamp TEXT, temp REAL)')
# Insert data with gaps
data = [
    ('2023-10-01 10:00:00', 20.0),
    ('2023-10-01 13:00:00', 26.0),
    ('2023-10-01 15:00:00', 25.0)
]
c.executemany('INSERT INTO readings VALUES (?, ?)', data)
conn.commit()
conn.close()

# 2. Create malformed JSONL file
jsonl_path = '/home/user/logs.jsonl'
with open(jsonl_path, 'w', encoding='utf-8') as f:
    f.write('{"ts": "2023-10-01 10:15:00", "msg": "Alert: high CPU usage!"}\n')
    f.write('{"ts": "2023-10-01 11:45:00", "msg": "Malformed \\uZZZZ sequence"}\n')
    f.write('{"ts": "2023-10-01 12:10:00", "msg": "All good."}\n')
    f.write('{"ts": "2023-10-01 13:05:00", "msg": "Shutdown \\u000g initiated."}\n')
    f.write('{"ts": "2023-10-01 14:30:00", "msg": "System is stable."}\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
