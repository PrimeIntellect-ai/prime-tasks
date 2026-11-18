#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsqlite3-dev sqlite3 gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import json

conn = sqlite3.connect('/home/user/sensor_data.db')
c = conn.cursor()

c.execute('''CREATE TABLE devices (id INTEGER PRIMARY KEY, name TEXT, location TEXT)''')
c.execute('''CREATE TABLE telemetry (id INTEGER PRIMARY KEY, device_id INTEGER, ts DATETIME, payload TEXT)''')
c.execute('''CREATE INDEX idx_telemetry_device_ts ON telemetry(device_id, ts)''')

devices = [
    (1, 'Alpha_Sensor', 'Zone_A'),
    (2, 'Beta_Sensor', 'Zone_B')
]
c.executemany("INSERT INTO devices VALUES (?, ?, ?)", devices)

telemetry = [
    (1, 1, '2023-10-01 10:00:00', json.dumps({"temp": 20.0, "humidity": 50})),
    (2, 1, '2023-10-01 10:05:00', json.dumps({"temp": 22.0, "humidity": 51})),
    (3, 1, '2023-10-01 10:10:00', json.dumps({"temp": 24.0, "humidity": 52})),
    (4, 1, '2023-10-01 10:15:00', json.dumps({"temp": 26.0, "humidity": 53})),
    (5, 2, '2023-10-01 10:00:00', json.dumps({"temp": 15.0, "humidity": 40})),
    (6, 2, '2023-10-01 10:05:00', json.dumps({"temp": 16.0, "humidity": 42})),
    (7, 2, '2023-10-01 10:10:00', json.dumps({"temp": 18.0, "humidity": 45})),
]
c.executemany("INSERT INTO telemetry VALUES (?, ?, ?, ?)", telemetry)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
