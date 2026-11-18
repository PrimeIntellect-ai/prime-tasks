#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/profiler
    cd /home/user/profiler

    cat << 'EOF' > setup_db.py
import sqlite3
import os

conn = sqlite3.connect('logs.db', isolation_level=None)
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('PRAGMA wal_autocheckpoint=0')
conn.execute('CREATE TABLE logs (id INTEGER PRIMARY KEY, metric INTEGER)')

# Insert 1000 rows, each with metric 2,500,000. Total = 2,500,000,000
for i in range(1, 1001):
    conn.execute(f"INSERT INTO logs (metric) VALUES (2500000)")

# Exit abruptly to leave the -wal file behind
os._exit(0)
EOF

    python3 setup_db.py
    rm setup_db.py

    cat << 'EOF' > process.py
import sqlite3
import multiprocessing
import json

def process_chunk(chunk, total_metric, processed_count):
    local_metric = 0
    local_count = 0
    for row in chunk:
        row_id, metric = row
        local_metric += metric
        local_count += 1

    # RACE CONDITION
    total_metric.value += local_metric
    processed_count.value += local_count

def main():
    conn = sqlite3.connect('/home/user/profiler/logs.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id, metric FROM logs")
    rows = cursor.fetchall()

    # integer overflow bug
    total_metric = multiprocessing.Value('i', 0)
    processed_count = multiprocessing.Value('i', 0)

    chunk_size = 50
    chunks = [rows[i:i + chunk_size] for i in range(0, len(rows), chunk_size)]

    processes = []
    for chunk in chunks:
        p = multiprocessing.Process(target=process_chunk, args=(chunk, total_metric, processed_count))
        processes.append(p)
        p.start()

    for p in processes:
        p.join()

    with open('/home/user/profiler/summary.json', 'w') as f:
        json.dump({
            "total_records": processed_count.value,
            "total_metric": total_metric.value
        }, f)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
