#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/telemetry.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE logs (id INTEGER PRIMARY KEY, device_id TEXT, epoch_sec INTEGER, signal_strength REAL)')

devices = [f'DEV-{str(i).zfill(3)}' for i in range(1, 11)]
data = []
id_counter = 1
for dev in devices:
    for _ in range(100):
        # Insert some valid and some invalid data
        sig = random.uniform(-110.0, 10.0)
        epoch = 1600000000 + random.randint(0, 10000)
        data.append((id_counter, dev, epoch, sig))
        id_counter += 1

# Add some specific predictable top values to verify against
data.append((id_counter, 'DEV-001', 1600000001, -1.5))
data.append((id_counter+1, 'DEV-001', 1600000002, -2.5))
data.append((id_counter+2, 'DEV-001', 1600000003, -3.5))

cursor.executemany('INSERT INTO logs VALUES (?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
