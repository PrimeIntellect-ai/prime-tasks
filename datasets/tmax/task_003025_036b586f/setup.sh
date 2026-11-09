#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server sqlite3
    pip3 install pytest redis

    mkdir -p /app

    # Start redis-server in background to populate it
    redis-server --daemonize yes
    sleep 2

    # Create setup_db.py
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/logs.db')
c = conn.cursor()
c.execute("CREATE TABLE user_logs(id INTEGER PRIMARY KEY, user_id INTEGER, action TEXT, timestamp DATETIME, duration INTEGER)")

actions = ['video_play', 'login', 'click']
batch = []
for i in range(500000):
    user_id = random.randint(1, 1000)
    action = random.choice(actions)
    duration = random.randint(10, 600) if action == 'video_play' else 0
    batch.append((user_id, action, '2023-01-01 10:00:00', duration))
    if len(batch) >= 10000:
        c.executemany("INSERT INTO user_logs(user_id, action, timestamp, duration) VALUES (?, ?, ?, ?)", batch)
        batch = []
if batch:
    c.executemany("INSERT INTO user_logs(user_id, action, timestamp, duration) VALUES (?, ?, ?, ?)", batch)

conn.commit()
conn.close()
EOF

    python3 /app/setup_db.py

    # Create producer.py
    cat << 'EOF' > /app/producer.py
import redis
import random

client = redis.Redis(host='127.0.0.1', port=6379, db=0)
for _ in range(500):
    client.lpush("job_queue", random.randint(1, 1000))
EOF

    python3 /app/producer.py

    # Create consumer.py
    cat << 'EOF' > /app/consumer.py
import redis
import sqlite3
import json

client = redis.Redis(host='127.0.0.1', port=6379, db=0)
conn = sqlite3.connect('/app/logs.db')
c = conn.cursor()

results = {}
while True:
    item = client.rpop("job_queue")
    if not item:
        break
    user_id = int(item)
    c.execute("SELECT SUM(duration) FROM user_logs WHERE user_id = ? AND action = 'video_play'", (user_id,))
    row = c.fetchone()
    total = row[0] if row[0] else 0
    results[str(user_id)] = total

with open('/app/results.json', 'w') as f:
    json.dump(results, f)
EOF

    # Save Redis data so it persists
    redis-cli save
    sleep 1

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/lib/redis
