#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = "/home/user/research.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE experiments (id INTEGER PRIMARY KEY, name TEXT, year INTEGER)")
c.execute("CREATE TABLE sensors (id INTEGER PRIMARY KEY, sensor_type TEXT)")
c.execute("CREATE TABLE samples (id INTEGER PRIMARY KEY, exp_id INTEGER, sensor_id INTEGER, measurement REAL)")

# Insert Experiments
experiments = []
for i in range(1, 21):
    year = 2023 if i % 2 == 0 else 2022
    experiments.append((i, f"Exp_{i}", year))
c.executemany("INSERT INTO experiments VALUES (?, ?, ?)", experiments)

# Insert Sensors
sensors = [(1, 'TypeA'), (2, 'TypeB'), (3, 'TypeC')]
c.executemany("INSERT INTO sensors VALUES (?, ?)", sensors)

# Insert Samples
random.seed(42)
samples = []
for i in range(1, 1001):
    exp_id = random.randint(1, 20)
    sensor_id = random.randint(1, 3)
    measurement = round(random.uniform(10.0, 100.0), 2)
    samples.append((i, exp_id, sensor_id, measurement))

c.executemany("INSERT INTO samples VALUES (?, ?, ?, ?)", samples)

# Create a "corrupted" index by creating it normally
c.execute("CREATE INDEX idx_samples_bad ON samples(exp_id)")

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
