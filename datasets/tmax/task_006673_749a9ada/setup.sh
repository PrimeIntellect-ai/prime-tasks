#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

# Create DB
db_path = '/home/user/research.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE participants (participant_id TEXT PRIMARY KEY, age INTEGER, cohort TEXT)''')
c.execute('''CREATE TABLE trials (trial_id TEXT PRIMARY KEY, participant_id TEXT, condition TEXT)''')

participants = [
    ('P001', 25, 'control'),
    ('P002', 30, 'treatment'),
    ('P003', 28, 'control'),
    ('P004', 35, 'control'),
    ('P005', 40, 'treatment')
]

trials = [
    ('T101', 'P001', 'fasting'),
    ('T102', 'P001', 'fed'),
    ('T103', 'P002', 'fasting'),
    ('T104', 'P003', 'fed'), # P003 is control but no fasting trial
    ('T105', 'P004', 'fasting'),
    ('T106', 'P004', 'fasting')
]

c.executemany('INSERT INTO participants VALUES (?, ?, ?)', participants)
c.executemany('INSERT INTO trials VALUES (?, ?, ?)', trials)
conn.commit()
conn.close()

# Create JSONL
jsonl_path = '/home/user/readings.jsonl'
readings = [
    {"trial_id": "T101", "timestamp": "10:00", "sensor_data": {"heart_rate": 70, "bp": 120}},
    {"trial_id": "T101", "timestamp": "10:05", "sensor_data": {"heart_rate": 75, "bp": 122}},
    {"trial_id": "T102", "timestamp": "12:00", "sensor_data": {"heart_rate": 80, "bp": 125}},
    {"trial_id": "T103", "timestamp": "09:00", "sensor_data": {"heart_rate": 65, "bp": 110}},
    {"trial_id": "T105", "timestamp": "10:00", "sensor_data": {"heart_rate": 68, "bp": 115}},
    {"trial_id": "T106", "timestamp": "11:00", "sensor_data": {"heart_rate": 72, "bp": 118}},
    {"trial_id": "T106", "timestamp": "11:05", "sensor_data": {"heart_rate": 70, "bp": 117}},
]

with open(jsonl_path, 'w') as f:
    for r in readings:
        f.write(json.dumps(r) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
