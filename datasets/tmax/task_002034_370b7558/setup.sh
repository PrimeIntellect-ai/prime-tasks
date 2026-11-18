#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /app/tiny_sql_builder
touch /app/tiny_sql_builder/__init__.py
cat << 'EOF' > /app/tiny_sql_builder/builder.py
class Window:
    def __init__(self, partition_by=None, order_by=None):
        self.partition_by = partition_by
        self.order_by = order_by
    def __str__(self):
        base = "OVER ("
        if self.partition_by: base += f"PARTITION BY {self.partition_by}"
        # BUG: missing order_by rendering
        return base + ")"
EOF

mkdir -p /opt/oracle
cat << 'EOF' > /opt/oracle/oracle.py
import sys
import json
import sqlite3

def main():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']:
        print(json.dumps({"results": []}))
        return

    conn = sqlite3.connect(':memory:')
    c = conn.cursor()
    c.execute('CREATE TABLE tx (tx_id TEXT, user_id INTEGER, status TEXT, timestamp INTEGER)')

    for line in lines:
        if not line.strip(): continue
        data = json.loads(line)
        c.execute('INSERT INTO tx VALUES (?, ?, ?, ?)', (data.get('tx_id'), data.get('user_id'), data.get('status'), data.get('timestamp')))

    query = """
    WITH Deadlocks AS (
        SELECT user_id, timestamp,
               LAG(timestamp) OVER (PARTITION BY user_id ORDER BY timestamp) as prev_ts
        FROM tx
        WHERE status = 'deadlock'
    )
    SELECT user_id, MAX(timestamp - prev_ts) as max_interval
    FROM Deadlocks
    WHERE prev_ts IS NOT NULL
    GROUP BY user_id
    ORDER BY user_id ASC
    """

    c.execute(query)
    results = [{"user_id": row[0], "max_deadlock_interval": row[1]} for row in c.fetchall()]
    print(json.dumps({"results": results}, indent=2))

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
