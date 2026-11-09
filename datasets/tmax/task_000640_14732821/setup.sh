#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest pandas

    mkdir -p /app

    # Generate audio file
    espeak -w /app/pm_request.wav "Hey, for the new report, make sure you join the users, transactions, and sessions tables. I need you to calculate the rolling 30-day average transaction amount per user using a window function. BUT, we only want to include users who have an active subscription tier of 'Premium' and have had at least one session lasting longer than 1000 seconds. Order the final output by the rolling average descending."

    # Create setup script to generate DB and golden report
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta
import pandas as pd

conn = sqlite3.connect('/app/company_data.db')
c = conn.cursor()

c.execute("CREATE TABLE users (user_id INTEGER, tier TEXT)")
c.execute("CREATE TABLE transactions (transaction_id INTEGER, user_id INTEGER, amount FLOAT, timestamp DATETIME)")
c.execute("CREATE TABLE sessions (session_id INTEGER, user_id INTEGER, duration_seconds INTEGER)")

random.seed(42)
tiers = ['Premium', 'Basic', 'Standard']
for i in range(1, 201):
    c.execute("INSERT INTO users VALUES (?, ?)", (i, random.choice(tiers)))

tx_id = 1
for i in range(1, 201):
    for _ in range(100):
        ts = datetime(2023, 1, 1) + timedelta(days=random.randint(0, 60), hours=random.randint(0, 23))
        c.execute("INSERT INTO transactions VALUES (?, ?, ?, ?)", (tx_id, i, random.uniform(10, 100), ts.strftime('%Y-%m-%d %H:%M:%S')))
        tx_id += 1

sess_id = 1
for i in range(1, 201):
    for _ in range(10):
        c.execute("INSERT INTO sessions VALUES (?, ?, ?)", (sess_id, i, random.randint(100, 2000)))
        sess_id += 1

conn.commit()

query = """
WITH valid_users AS (
    SELECT DISTINCT u.user_id
    FROM users u
    JOIN sessions s ON u.user_id = s.user_id
    WHERE u.tier = 'Premium' AND s.duration_seconds > 1000
)
SELECT t.user_id, t.timestamp, 
       AVG(t.amount) OVER (PARTITION BY t.user_id ORDER BY julianday(t.timestamp)
                           RANGE BETWEEN 30 PRECEDING AND CURRENT ROW) as rolling_avg
FROM transactions t
JOIN valid_users vu ON t.user_id = vu.user_id
ORDER BY rolling_avg DESC
"""
df = pd.read_sql_query(query, conn)
df.to_csv('/app/golden_report.csv', index=False)
conn.close()
EOF

    python3 /app/setup_db.py

    # Create naive report
    cat << 'EOF' > /app/naive_report.py
import sqlite3
import pandas as pd
import time

conn = sqlite3.connect('/app/company_data.db')
c = conn.cursor()

c.execute("SELECT user_id, tier FROM users")
users = c.fetchall()

results = []
for user_id, tier in users:
    if tier != 'Premium':
        continue

    c.execute("SELECT duration_seconds FROM sessions WHERE user_id=?", (user_id,))
    sessions = c.fetchall()
    if not any(s[0] > 1000 for s in sessions):
        continue

    c.execute("SELECT amount, timestamp FROM transactions WHERE user_id=? ORDER BY timestamp", (user_id,))
    txs = c.fetchall()

    time.sleep(0.1) # Simulate slow N+1 network overhead

    for i in range(len(txs)):
        current_jd = pd.Timestamp(txs[i][1]).to_julian_date()
        total = 0
        count = 0
        for j in range(i, -1, -1):
            prev_jd = pd.Timestamp(txs[j][1]).to_julian_date()
            if (current_jd - prev_jd) <= 30:
                total += txs[j][0]
                count += 1
            else:
                break
        rolling_avg = total / count
        results.append((user_id, txs[i][1], rolling_avg))

df = pd.DataFrame(results, columns=['user_id', 'timestamp', 'rolling_avg'])
df = df.sort_values(by='rolling_avg', ascending=False)
df.to_csv('/app/naive_output.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
