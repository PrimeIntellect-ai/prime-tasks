#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json

db_path = '/home/user/sensor_data.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE readings
             (id INTEGER PRIMARY KEY, station_id TEXT, timestamp TEXT, payload TEXT)''')

data = [
    (1, 'ST-01', '2023-10-01 10:00:00', json.dumps({"temperature": 20.0, "humidity": 50})),
    (2, 'ST-01', '2023-10-01 14:00:00', json.dumps({"temperature": 22.5, "humidity": 45})),
    (3, 'ST-01', '2023-10-02 09:00:00', json.dumps({"temperature": 19.0, "humidity": 60})),
    (4, 'ST-01', '2023-10-02 15:00:00', 'invalid json'),
    (5, 'ST-01', '2023-10-02 16:00:00', json.dumps({"temperature": 25.0, "humidity": None})),
    (6, 'ST-01', '2023-10-03 10:00:00', json.dumps({"temperature": 21.0, "humidity": 55})),
    (7, 'ST-02', '2023-10-01 10:00:00', json.dumps({"temperature": 30.0, "humidity": 20})),
    (8, 'ST-01', '2023-10-03 12:00:00', json.dumps({"temperature": 28.0, "humidity": 50})) 
]

c.executemany('INSERT INTO readings VALUES (?, ?, ?, ?)', data)

c.execute("CREATE INDEX idx_timestamp ON readings(timestamp) WHERE id != 8")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
