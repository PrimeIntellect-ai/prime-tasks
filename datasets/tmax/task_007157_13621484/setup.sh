#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

db_path = "/home/user/research.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("CREATE TABLE locations (id INTEGER PRIMARY KEY, name TEXT, region TEXT)")
cur.execute("CREATE TABLE researchers (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
cur.execute("CREATE TABLE samples (id INTEGER PRIMARY KEY, location_id INTEGER, researcher_id INTEGER, collection_date TEXT, type TEXT)")
cur.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, sample_id INTEGER, metric_name TEXT, value REAL)")

# Insert locations
regions = ['Polar', 'Tundra', 'Tropical', 'Arid']
for i in range(1, 21):
    region = 'Polar' if i <= 5 else random.choice(regions)
    cur.execute("INSERT INTO locations VALUES (?, ?, ?)", (i, f"Loc_{i}", region))

# Insert researchers
for i in range(1, 11):
    cur.execute("INSERT INTO researchers VALUES (?, ?, ?)", (i, f"Res_{i}", "Climatology"))

# Insert samples
random.seed(42)
start_date = datetime(2000, 1, 1)
for i in range(1, 2001):
    loc_id = random.randint(1, 20)
    res_id = random.randint(1, 10)
    days = random.randint(0, 7000)
    c_date = (start_date + timedelta(days=days)).strftime("%Y-%m-%d")
    stype = 'ice_core' if random.random() < 0.3 else 'soil'
    cur.execute("INSERT INTO samples VALUES (?, ?, ?, ?, ?)", (i, loc_id, res_id, c_date, stype))

# Insert measurements
for i in range(1, 10001):
    samp_id = random.randint(1, 2000)
    metric = 'carbon_ppm' if random.random() < 0.5 else 'temperature'
    val = round(random.uniform(200.0, 500.0), 2)
    cur.execute("INSERT INTO measurements VALUES (?, ?, ?, ?)", (i, samp_id, metric, val))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
