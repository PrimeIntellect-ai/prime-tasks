#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg sqlite3
    pip3 install pytest pymongo pydantic

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update && apt-get install -y mongodb-org

    mkdir -p /home/user

    cat << 'EOF' > /home/user/seed.json
[
    {"user_id": "U001", "action": "login", "timestamp": "2023-10-01T10:00:00Z"},
    {"user_id": "U001", "action": "click", "timestamp": "2023-10-01T10:05:00Z"},
    {"user_id": "U002", "action": "login", "timestamp": "2023-10-01T10:01:00Z"},
    {"user_id": "U003", "action": "login", "timestamp": "2023-10-01T10:02:00Z"},
    {"user_id": "U001", "action": "logout", "timestamp": "2023-10-01T11:00:00Z"},
    {"user_id": "U002", "action": "logout", "timestamp": "2023-10-01T11:30:00Z"},
    {"user_id": "U004", "action": "login"}, 
    {"user_id": 12345, "action": "invalid_type", "timestamp": "2023-10-01T10:00:00Z"}
]
EOF

    cat << 'EOF' > /home/user/backup_mapper.py
import sqlite3
import threading
from pymongo import MongoClient

# MongoDB setup
client = MongoClient("mongodb://localhost:27017/")
db = client["analytics_db"]
collection = db["activity_logs"]

# SQLite setup
conn = sqlite3.connect('/home/user/analytics.db', check_same_thread=False)
cursor = conn.cursor()
cursor.execute('''
    CREATE TABLE IF NOT EXISTS user_summary (
        user_id TEXT PRIMARY KEY,
        total_actions INTEGER,
        latest_action_date TEXT
    )
''')
conn.commit()

# Aggregation pipeline
pipeline = [
    {"$group": {
        "_id": "$user_id",
        "total_actions": {"$sum": 1},
        "latest_action_date": {"$max": "$timestamp"}
    }}
]

results = list(collection.aggregate(pipeline))

# Broken threaded insert logic (Causes deadlock/locking issues)
def insert_worker(record):
    local_conn = sqlite3.connect('/home/user/analytics.db')
    local_cursor = local_conn.cursor()
    local_cursor.execute("BEGIN EXCLUSIVE")
    local_cursor.execute('''
        INSERT OR REPLACE INTO user_summary (user_id, total_actions, latest_action_date)
        VALUES (?, ?, ?)
    ''', (str(record["_id"]), record["total_actions"], record.get("latest_action_date", "")))
    # Missing explicit commits or lock releases in the right place
    local_conn.commit()
    local_conn.close()

threads = []
for r in results:
    t = threading.Thread(target=insert_worker, args=(r,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

print("Migration complete!")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
