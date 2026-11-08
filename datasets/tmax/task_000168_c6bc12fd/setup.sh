#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest flask requests

    mkdir -p /app/logs /app/db /app/src

    # Create dummy video file
    dd if=/dev/zero of=/app/crash_evidence.mp4 bs=1M count=1

    # Create the log file with the traceback
    cat << 'EOF' > /app/logs/service.log
2023-10-27 03:00:01 ERROR: Crash occurred while processing /app/crash_evidence.mp4
Traceback (most recent call last):
  File "/app/src/server.py", line 42, in process_video
    cur.execute(f"INSERT INTO frames (timestamp, metadata) VALUES ({timestamp}, '{metadata}')")
sqlite3.OperationalError: near "s": syntax error
EOF

    # Create the buggy server.py
    cat << 'EOF' > /app/src/server.py
from flask import Flask, jsonify
import sqlite3

app = Flask(__name__)
DB_PATH = '/app/db/indexer.db'

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/api/frames/count')
def count():
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM frames")
        count = cur.fetchone()[0]
        return jsonify({"count": count})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def process_video(filepath):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    # Buggy query using string formatting
    timestamp = 4.71
    metadata = "frame_data_with_an_unescaped_single_quote's_here"
    cur.execute(f"INSERT INTO frames (timestamp, metadata) VALUES ({timestamp}, '{metadata}')")
    conn.commit()

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Generate the SQLite database and WAL
    python3 -c "
import sqlite3
import os
conn = sqlite3.connect('/app/db/indexer.db')
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE frames (id INTEGER PRIMARY KEY, timestamp REAL, metadata TEXT);')
conn.commit()
for i in range(1, 143):
    conn.execute('INSERT INTO frames (id, timestamp, metadata) VALUES (?, ?, ?)', (i, i*0.033, 'frame_data'))
conn.commit()
os._exit(0)
"

    # Ensure WAL file exists even if Python cleaned it up
    touch /app/db/indexer.db-wal

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
