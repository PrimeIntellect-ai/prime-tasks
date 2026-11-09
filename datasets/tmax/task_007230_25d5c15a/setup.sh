#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_monitor
    cat << 'EOF' > /home/user/uptime_monitor/app.py
import sqlite3

def get_metrics():
    conn = sqlite3.connect('/home/user/uptime_monitor/metrics.db')
    c = conn.cursor()
    # BUG 1: The join condition is wrong, causing a Cartesian product/duplicate rows
    # Should be: ON h.server_id = s.id
    c.execute('''
        SELECT h.timestamp, h.status 
        FROM heartbeats h 
        JOIN servers s ON 1=1
        ORDER BY h.timestamp ASC
    ''')
    return c.fetchall()

def calculate_uptime(rows):
    if not rows:
        return {"uptime": 0.0}

    # BUG 3: Bad initialization
    # ema should start at the first value
    prev_timestamp = rows[0][0]
    ema = None

    for row in rows:
        timestamp, status = row
        val = 1.0 if status == 'UP' else 0.0

        if ema is None:
            ema = val
            continue

        time_diff = timestamp - prev_timestamp
        # BUG 2: Zero division if duplicate timestamps exist
        weight = 1.0 / time_diff 

        alpha = min(weight * 0.1, 1.0)
        ema = (val * alpha) + (ema * (1 - alpha))
        prev_timestamp = timestamp

    return {"final_uptime_score": round(ema, 4)}

if __name__ == '__main__':
    rows = get_metrics()
    result = calculate_uptime(rows)
    print(result)
EOF

    sqlite3 /home/user/uptime_monitor/metrics.db << 'EOF'
CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE heartbeats (id INTEGER PRIMARY KEY, server_id INTEGER, timestamp REAL, status TEXT);

INSERT INTO servers (id, name) VALUES (1, 'web-01');
INSERT INTO servers (id, name) VALUES (2, 'web-02');

INSERT INTO heartbeats (server_id, timestamp, status) VALUES (1, 1600000000.0, 'UP');
INSERT INTO heartbeats (server_id, timestamp, status) VALUES (1, 1600000010.0, 'UP');
INSERT INTO heartbeats (server_id, timestamp, status) VALUES (1, 1600000020.0, 'DOWN');
INSERT INTO heartbeats (server_id, timestamp, status) VALUES (1, 1600000030.0, 'UP');
INSERT INTO heartbeats (server_id, timestamp, status) VALUES (1, 1600000040.0, 'UP');
EOF

    chmod -R 777 /home/user
