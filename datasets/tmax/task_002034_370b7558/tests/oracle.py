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
