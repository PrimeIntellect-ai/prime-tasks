#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
import datetime

db_path = "/home/user/backup_metadata.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE backup_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    server_name TEXT,
    backup_timestamp DATETIME,
    status TEXT,
    backup_size_bytes INTEGER,
    duration_seconds INTEGER
)
''')

# Generate data
servers = [f"db-server-{i:02d}" for i in range(1, 11)]
statuses = ["SUCCESS", "FAILED"]
base_time = datetime.datetime(2023, 10, 1)

records = []
for server in servers:
    for day in range(30):
        ts = base_time + datetime.timedelta(days=day)
        # Force the last 3 days of db-server-04 to be an anomaly
        if server == "db-server-04" and day == 29:
            size = 100000000  # 100MB
            status = "SUCCESS"
        elif server == "db-server-04" and day in [27, 28]:
            size = 20000000   # 20MB
            status = "SUCCESS"
        else:
            size = random.randint(15000000, 25000000)
            status = random.choices(statuses, weights=[0.9, 0.1])[0]

        records.append((server, ts.isoformat(), status, size, random.randint(300, 3600)))

cursor.executemany('''
INSERT INTO backup_logs (server_name, backup_timestamp, status, backup_size_bytes, duration_seconds)
VALUES (?, ?, ?, ?, ?)
''', records)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
