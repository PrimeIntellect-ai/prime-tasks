#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = '/home/user/analytics.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, tenant_id TEXT, name TEXT, created_at TEXT)")
c.execute("CREATE TABLE sessions (id INTEGER PRIMARY KEY, user_id INTEGER, start_time TEXT, end_time TEXT, device_type TEXT)")
c.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, session_id INTEGER, event_type TEXT, timestamp TEXT, value REAL)")

random.seed(42)
users = []
for i in range(1, 1001):
    tenant = f"tenant_{random.randint(1, 50)}"
    name = f"User_{i}"
    users.append((i, tenant, name, "2023-01-01"))
c.executemany("INSERT INTO users VALUES (?, ?, ?, ?)", users)

sessions = []
for i in range(1, 5001):
    user_id = random.randint(1, 1000)
    device = random.choice(['mobile', 'desktop', 'tablet'])
    sessions.append((i, user_id, "2023-01-01", "2023-01-01", device))
c.executemany("INSERT INTO sessions VALUES (?, ?, ?, ?, ?)", sessions)

events = []
for i in range(1, 20001):
    session_id = random.randint(1, 5000)
    event_type = random.choice(['click', 'view', 'purchase', 'login'])
    value = round(random.uniform(10.0, 500.0), 2) if event_type == 'purchase' else 0.0
    events.append((i, session_id, event_type, "2023-01-01", value))
c.executemany("INSERT INTO events VALUES (?, ?, ?, ?, ?)", events)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
