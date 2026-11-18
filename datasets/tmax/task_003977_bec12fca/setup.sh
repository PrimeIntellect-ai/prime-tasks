#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/intercept.wav "Alert triggered for unauthorized access by user ID eight zero four one."

    python3 -c "
import sqlite3
import random

conn = sqlite3.connect('/app/audit.db')
c = conn.cursor()
c.execute('CREATE TABLE systems (sys_id INTEGER PRIMARY KEY, ip_address TEXT, hostname TEXT);')
c.execute('CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, source_sys_id INTEGER, dest_sys_id INTEGER, user_id INTEGER, timestamp DATETIME, duration_seconds INTEGER);')

systems = [(1, '10.0.0.1', 'entry.corp.local')]
for i in range(2, 10001):
    systems.append((i, f'10.0.0.{i}', f'sys{i}.corp.local'))
c.executemany('INSERT INTO systems VALUES (?, ?, ?)', systems)

logs = []
log_id = 1
# Path for 8041 of length 4: 1 -> 2 -> 3 -> 4 -> 5
logs.append((log_id, 1, 2, 8041, '2023-01-01 10:00:00', 10)); log_id += 1
logs.append((log_id, 2, 3, 8041, '2023-01-01 10:05:00', 15)); log_id += 1
logs.append((log_id, 3, 4, 8041, '2023-01-01 10:10:00', 20)); log_id += 1
logs.append((log_id, 4, 5, 8041, '2023-01-01 10:15:00', 25)); log_id += 1

for _ in range(50000):
    src = random.randint(1, 10000)
    dst = random.randint(1, 10000)
    usr = random.randint(1000, 9000)
    logs.append((log_id, src, dst, usr, '2023-01-01 12:00:00', random.randint(1, 100)))
    log_id += 1

c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?, ?, ?)', logs)
conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
