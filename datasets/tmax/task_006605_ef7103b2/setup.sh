#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/sensor_data.db "CREATE TABLE readings (id INTEGER PRIMARY KEY, sensor_id TEXT, timestamp DATETIME, value REAL, batch TEXT);"
    sqlite3 /home/user/sensor_data.db "INSERT INTO readings (sensor_id, timestamp, value, batch) VALUES ('S-100', '2023-01-15 10:00:00', 45.2, 'B-52');"
    sqlite3 /home/user/sensor_data.db "INSERT INTO readings (sensor_id, timestamp, value, batch) VALUES ('S-101', '2023-01-16 10:00:00', 46.2, 'B-53');"

    cat << 'EOF' > /home/user/process_results.py
import sqlite3

def get_sensor_history(db_path, sensor_id, start_time, end_time):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    query = f"SELECT timestamp, value FROM readings WHERE sensor_id = '{sensor_id}' AND timestamp >= '{start_time}' AND timestamp <= '{end_time}' ORDER BY timestamp ASC"
    c.execute(query)
    results = c.fetchall()
    conn.close()
    return results

def get_batch_stats(db_path, batch_id):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    query = "SELECT COUNT(*), AVG(value) FROM readings WHERE batch = '{}'".format(batch_id)
    c.execute(query)
    results = c.fetchone()
    conn.close()
    return results
EOF

    chmod -R 777 /home/user
