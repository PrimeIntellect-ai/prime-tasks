#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app

    # Generate voicemail.wav
    espeak -w /app/voicemail.wav "The relationships table index is completely corrupted. Do not use it. To find the correct active edges, you must query the 'audit_log_edges' table. Group by the source and target node IDs, and only include the edge if the most recent event type is 'LINK_UP'."

    # Create network.db
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/network.db')
c = conn.cursor()
c.execute('CREATE TABLE relationships (source_id VARCHAR, target_id VARCHAR)')
c.execute('CREATE TABLE audit_log_edges (id INTEGER PRIMARY KEY, source_id VARCHAR, target_id VARCHAR, event_type VARCHAR, timestamp INTEGER)')

for i in range(1, 101):
    c.execute('INSERT INTO relationships VALUES (?, ?)', (f'NODE_{i:03}', f'NODE_{random.randint(1,100):03}'))

ts = 1000
for i in range(1, 101):
    source = f'NODE_{i:03}'
    for j in range(5):
        target = f'NODE_{random.randint(1,100):03}'
        c.execute('INSERT INTO audit_log_edges (source_id, target_id, event_type, timestamp) VALUES (?, ?, ?, ?)', (source, target, 'LINK_UP', ts))
        ts += 1
        if random.random() > 0.5:
            c.execute('INSERT INTO audit_log_edges (source_id, target_id, event_type, timestamp) VALUES (?, ?, ?, ?)', (source, target, 'LINK_DOWN', ts))
            ts += 1

conn.commit()
conn.close()
EOF
    python3 /app/setup_db.py
    rm /app/setup_db.py

    # Create oracle.py
    cat << 'EOF' > /app/oracle.py
import sys
import sqlite3
import json

def get_edges(node_id):
    conn = sqlite3.connect('/app/network.db')
    cursor = conn.cursor()
    query = """
    SELECT target_id, event_type
    FROM audit_log_edges
    WHERE source_id = ?
    ORDER BY timestamp DESC
    """
    cursor.execute(query, (node_id,))
    rows = cursor.fetchall()

    # Keep only the latest event for each target
    latest_events = {}
    for target_id, event_type in rows:
        if target_id not in latest_events:
            latest_events[target_id] = event_type

    # Filter where latest event is LINK_UP
    active_targets = [tid for tid, ev in latest_events.items() if ev == 'LINK_UP']
    active_targets.sort()

    print(json.dumps(active_targets))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        get_edges(sys.argv[1])
    else:
        print("[]")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
