#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import random
import datetime

db_path = "/home/user/climate_data.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE locations (id INTEGER PRIMARY KEY, region_name TEXT, elevation REAL)")
c.execute("CREATE TABLE sensors (id INTEGER PRIMARY KEY, type TEXT, location_id INTEGER)")
c.execute("CREATE TABLE readings (id INTEGER PRIMARY KEY, sensor_id INTEGER, timestamp TEXT, value REAL)")

regions = ['Alpine_Zone', 'Valley', 'Desert', 'Coastal']
for i, r in enumerate(regions):
    c.execute("INSERT INTO locations (id, region_name, elevation) VALUES (?, ?, ?)", (i+1, r, random.uniform(100, 3000)))

# Insert 10 sensors
for i in range(1, 11):
    loc_id = 1 if i <= 3 else random.randint(2, 4)
    stype = 'TEMP' if i % 2 != 0 else 'HUMIDITY'
    c.execute("INSERT INTO sensors (id, type, location_id) VALUES (?, ?, ?)", (i, stype, loc_id))

# Insert readings
base_time = datetime.datetime(2023, 1, 1, 0, 0, 0)
for sid in range(1, 11):
    for j in range(20): # 20 readings each
        ts = (base_time + datetime.timedelta(hours=j)).isoformat()
        val = round(random.uniform(-10, 30), 2)
        c.execute("INSERT INTO readings (sensor_id, timestamp, value) VALUES (?, ?, ?)", (sid, ts, val))

conn.commit()
conn.close()

# Create the unoptimized python script
with open("/home/user/generate_report.py", "w") as f:
    f.write('''import sqlite3
import json

def run():
    conn = sqlite3.connect('/home/user/climate_data.db')
    c = conn.cursor()
    # Extremely bad approach
    locations = c.execute("SELECT * FROM locations").fetchall()
    sensors = c.execute("SELECT * FROM sensors").fetchall()
    readings = c.execute("SELECT * FROM readings").fetchall()

    # ... (agent needs to rewrite this anyway)

if __name__ == "__main__":
    run()
''')
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
