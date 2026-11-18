#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
from datetime import datetime, timedelta

conn = sqlite3.connect('/home/user/metrics.db')
c = conn.cursor()
c.execute('''CREATE TABLE api_requests
             (id INTEGER PRIMARY KEY, endpoint TEXT, response_time_ms REAL, timestamp DATETIME)''')

base_time = datetime(2023, 10, 1, 12, 0, 0)
endpoints = ["/api/checkout", "/api/users", "/api/checkout", "/api/products", "/api/checkout", "/api/checkout", "/api/checkout", "/api/checkout", "/api/checkout", "/api/checkout"]
times = [150.5, 50.0, 160.0, 45.0, 200.0, 210.0, 190.0, 300.0, 120.0, 125.0]

for i in range(10):
    c.execute("INSERT INTO api_requests (endpoint, response_time_ms, timestamp) VALUES (?, ?, ?)",
              (endpoints[i], times[i], (base_time + timedelta(minutes=i)).strftime('%Y-%m-%d %H:%M:%S')))

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
