#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import sqlite3
import csv
import os

os.makedirs('/home/user', exist_ok=True)

# temp_sensors.csv
with open('/home/user/temp_sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'machine_id', 'temperature'])
    writer.writerows([
        ['2023-10-01T01:15:00Z', 'M1', 40.0],
        ['2023-10-01T01:45:00Z', 'M1', 42.0],
        ['2023-10-01T02:30:00Z', 'M1', 44.0],
        ['2023-10-01T03:10:00Z', 'M1', 46.0],
        ['2023-10-01T04:20:00Z', 'M1', 50.0],
        ['2023-10-01T01:30:00Z', 'M2', 99.0],
        ['2023-10-01T01:10:00Z', 'M3', 55.0],
        ['2023-10-01T03:15:00Z', 'M3', 60.0],
    ])

# humidity_sensors.csv
with open('/home/user/humidity_sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'machine_id', 'humidity'])
    writer.writerows([
        ['2023-10-01T01:20:00Z', 'M1', 30.0],
        ['2023-10-01T02:15:00Z', 'M1', 32.0],
        ['2023-10-01T03:40:00Z', 'M1', 34.0],
        ['2023-10-01T04:10:00Z', 'M1', 36.0],
        ['2023-10-01T01:30:00Z', 'M2', 99.0],
        ['2023-10-01T01:40:00Z', 'M3', 45.0], 
        ['2023-10-01T02:15:00Z', 'M3', 46.0],
        ['2023-10-01T03:20:00Z', 'M3', 50.0],
    ])

# maintenance.db
conn = sqlite3.connect('/home/user/maintenance.db')
c = conn.cursor()
c.execute('''CREATE TABLE maintenance_logs (machine_id TEXT, last_service_date TEXT, status TEXT)''')
c.executemany('INSERT INTO maintenance_logs VALUES (?,?,?)', [
    ('M1', '2023-09-01T00:00:00Z', 'ACTIVE'),
    ('M2', '2023-09-01T00:00:00Z', 'DECOMMISSIONED'),
    ('M3', '2023-09-15T00:00:00Z', 'MAINTENANCE_REQUIRED'),
])
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
