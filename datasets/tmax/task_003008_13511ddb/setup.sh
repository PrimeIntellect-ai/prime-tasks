#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import sqlite3
import csv

# Create DB
conn = sqlite3.connect('/home/user/data/observations.db')
c = conn.cursor()
c.execute('CREATE TABLE sensors (sensor_id INTEGER PRIMARY KEY, location TEXT, sensor_type TEXT)')
c.execute('CREATE TABLE readings (reading_id INTEGER PRIMARY KEY, sensor_id INTEGER, timestamp DATETIME, raw_value FLOAT)')

sensors = [
    (1, 'Site A', 'Temperature'),
    (2, 'Site B', 'Temperature'),
    (3, 'Site A', 'Humidity'),
    (4, 'Site C', 'Pressure')
]
c.executemany('INSERT INTO sensors VALUES (?, ?, ?)', sensors)

readings = [
    (1, 1, '2023-10-01 08:00:00', 20.5),
    (2, 1, '2023-10-01 14:00:00', 22.0),
    (3, 2, '2023-10-01 10:00:00', 19.8),
    (4, 3, '2023-10-01 09:00:00', 55.0),
    (5, 4, '2023-10-02 08:00:00', 1012.5),
    (6, 1, '2023-10-02 12:00:00', 21.0),
    (7, 2, '2023-10-02 16:00:00', 20.0)
]
c.executemany('INSERT INTO readings VALUES (?, ?, ?, ?)', readings)
conn.commit()
conn.close()

# Create CSV
with open('/home/user/data/calibration.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['sensor_id', 'correction_factor'])
    writer.writerow([1, 1.05])
    writer.writerow([2, 0.98])
    writer.writerow([3, 1.02])
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
