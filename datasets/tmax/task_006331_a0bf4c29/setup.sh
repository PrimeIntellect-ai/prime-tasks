#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

db_path = "/home/user/telemetry.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
    CREATE TABLE IF NOT EXISTS sensor_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensor_id TEXT,
        timestamp TEXT,
        reading REAL,
        status TEXT
    )
''')

statuses = ["OK", "WARN", "ERROR"]
sensors = ["SENS-01", "SENS-02", "SENS-03", "SENS-04"]

base_time = datetime(2023, 10, 1, 0, 0, 0)
data = []

random.seed(42)

for i in range(1000):
    sensor = random.choice(sensors)
    dt = base_time + timedelta(minutes=i*5)
    reading = round(random.uniform(10.0, 150.0), 2)
    # Ensure some ERRORs exist
    if i % 15 == 0:
        status = "ERROR"
    else:
        status = random.choice(statuses)

    data.append((sensor, dt.strftime("%Y-%m-%dT%H:%M:%SZ"), reading, status))

cursor.executemany('''
    INSERT INTO sensor_data (sensor_id, timestamp, reading, status)
    VALUES (?, ?, ?, ?)
''', data)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py

    chmod -R 777 /home/user
