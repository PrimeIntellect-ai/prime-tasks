#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

conn = sqlite3.connect('access_logs.db')
c = conn.cursor()

c.execute('''CREATE TABLE user_access
             (id INTEGER PRIMARY KEY, username TEXT, ip_address TEXT, timestamp DATETIME, status TEXT)''')

statuses = ['success', 'success', 'success', 'failed']
start_time = datetime(2023, 1, 1)

records = []
for i in range(1, 1001):
    user = f"user_{random.randint(1, 50)}"
    ip = f"192.168.1.{random.randint(1, 255)}"
    ts = start_time + timedelta(minutes=i*15)
    # Ensure specific failed records for verification
    if i > 950:
        status = 'failed' if i % 2 == 0 else 'success'
    else:
        status = random.choice(statuses)
    records.append((user, ip, ts.isoformat(), status))

c.executemany("INSERT INTO user_access (username, ip_address, timestamp, status) VALUES (?, ?, ?, ?)", records)
conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
