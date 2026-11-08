#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk bc
    pip3 install pytest pandas scikit-learn

    mkdir -p /app /home/user

    python3 -c "
import sqlite3
import random
import datetime
import os
import csv
import shutil

os.makedirs('/app', exist_ok=True)
os.makedirs('/home/user', exist_ok=True)

with open('/app/telemetry_aggregator', 'w') as f:
    f.write('dummy')

with open('/home/user/crash.dmp', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'CALIBRATION_FACTOR_SCALAR:1.875329\x00')
    f.write(os.urandom(1024))

db_path = '/home/user/telemetry.db'
conn = sqlite3.connect(db_path)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE metrics(timestamp TEXT, value REAL);')

records = []
start_time = datetime.datetime(2023, 1, 1, 12, 0, 0)
for i in range(100):
    ts = (start_time + datetime.timedelta(seconds=i)).strftime('%Y-%m-%d %H:%M:%S')
    val = random.uniform(10.0, 50.0)
    records.append((ts, val))

conn.executemany('INSERT INTO metrics VALUES (?, ?)', records)
conn.commit()

with open('/app/reference_metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'value'])
    for ts, val in records:
        writer.writerow([ts, val * 1.875329])

shutil.copyfile('/home/user/telemetry.db-wal', '/tmp/wal')
conn.close()
shutil.move('/tmp/wal', '/home/user/telemetry.db-wal')

with open(db_path, 'r+b') as f:
    f.write(os.urandom(100))
"

    chmod 700 /app/reference_metrics.csv
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
