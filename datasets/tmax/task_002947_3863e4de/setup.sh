#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import sqlite3
import json
import random
import math

db_path = "/home/user/telemetry.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("CREATE TABLE readings (id INTEGER PRIMARY KEY, payload BLOB)")

random.seed(42)
anomalous_ids = []

temps = []
# Generate normal data
for i in range(1, 101):
    temp = random.normalvariate(20.0, 2.0)
    temps.append(temp)
    payload = json.dumps({"temp": temp, "status": "ok"}).encode('utf-8')
    cur.execute("INSERT INTO readings (id, payload) VALUES (?, ?)", (i, payload))

# Generate legacy encoded data (latin-1) with some normal and some anomalous temps
for i in range(101, 121):
    if i in [105, 112, 118]:
        # Anomalies
        temp = 85.0 + random.random() * 10
        anomalous_ids.append(i)
    else:
        temp = random.normalvariate(20.0, 2.0)

    temps.append(temp)
    # Using latin-1 specific byte to ensure utf-8 decode fails
    payload_str = json.dumps({"temp": temp, "status": "legacy", "note": "t°"})
    payload = payload_str.encode('latin-1')
    cur.execute("INSERT INTO readings (id, payload) VALUES (?, ?)", (i, payload))

conn.commit()
conn.close()

# Corrupt the database slightly at the end to cause malformed error on some operations,
# but allow .dump to extract the data.
with open(db_path, "r+b") as f:
    f.seek(100)
    f.write(b"GARBAGE_DATA_CORRUPTION")

# Create the broken triage script
triage_script = """import sqlite3
import json
import statistics

def main():
    conn = sqlite3.connect('/home/user/telemetry.db')
    cur = conn.cursor()

    cur.execute("SELECT id, payload FROM readings")
    rows = cur.fetchall()

    parsed_data = []
    for row in rows:
        row_id = row[0]
        # This will crash on latin-1 encoded payloads
        payload_str = row[1].decode('utf-8')
        data = json.loads(payload_str)
        parsed_data.append((row_id, data['temp']))

    # TODO: Calculate mean and stdev of temperatures
    # TODO: Find anomalies (Z-score > 3)
    # TODO: Write anomalous IDs to /home/user/anomalies.txt

if __name__ == "__main__":
    main()
"""

with open("/home/user/triage.py", "w") as f:
    f.write(triage_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
