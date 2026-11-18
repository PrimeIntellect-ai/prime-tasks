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

db_path = '/home/user/events.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE daily_metrics (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    record_date TEXT,
    metric_value REAL
)''')

start_date = datetime(2023, 10, 1)
data = []
# Create predictable data for user_id 5
for i in range(10):
    date_str = (start_date + timedelta(days=i)).strftime('%Y-%m-%d')
    data.append((5, date_str, float(i + 1))) # values 1.0 to 10.0

# Add noise for other users
for user in [1, 2, 3]:
    for i in range(5):
        date_str = (start_date + timedelta(days=i)).strftime('%Y-%m-%d')
        data.append((user, date_str, float(i * 2)))

conn.executemany("INSERT INTO daily_metrics (user_id, record_date, metric_value) VALUES (?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
