#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/data

    cat << 'EOF' > /home/user/setup_task.py
import sqlite3
import time
import random
from datetime import datetime, timezone

# 1. Generate Logs
logs_dir = "/home/user/logs"
t0 = 1698240000 # 2023-10-25T13:20:00Z

with open(f"{logs_dir}/gateway.log", "w") as f_gw, \
     open(f"{logs_dir}/aggregator.log", "w") as f_ag, \
     open(f"{logs_dir}/db_writer.log", "w") as f_db:

     # Write interleaved logs
     f_gw.write(f"{t0 + 10} INFO Gateway started\n")
     f_ag.write(f"2023-10-25T13:20:15Z INFO Aggregator started\n")
     f_db.write(f"2023/10/25 13:20:20 INFO DB Writer started\n")

     f_gw.write(f"{t0 + 60} INFO Receiving data\n")
     f_ag.write(f"2023-10-25T13:21:05Z WARN Buffer filling up\n")
     f_db.write(f"2023/10/25 13:21:10 INFO Committing transaction\n")

     # Crash logs
     f_gw.write(f"{t0 + 120} ERROR Connection lost\n")
     f_db.write(f"2023/10/25 13:22:05 FATAL Disk write failure\n")

# 2. Generate Database
db_path = "/home/user/data/sensors.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE readings (id INTEGER PRIMARY KEY, sensor_id TEXT, timestamp REAL, value REAL)")

sensors = ["sensor_01", "sensor_02", "sensor_03", "sensor_04"]
random.seed(42)

for i in range(100):
    for s in sensors:
        # Normal variance ~ 1.0
        val = 20.0 + random.uniform(-1.0, 1.0)
        c.execute("INSERT INTO readings (sensor_id, timestamp, value) VALUES (?, ?, ?)", (s, t0 + i, val))

# Insert anomalous sensor data
for i in range(100):
    # Anomalous variance ~ 50.0
    val = 20.0 + random.uniform(-50.0, 50.0)
    c.execute("INSERT INTO readings (sensor_id, timestamp, value) VALUES (?, ?, ?)", ("sensor_03", t0 + i, val))

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_task.py
    rm /home/user/setup_task.py

    chmod -R 777 /home/user
