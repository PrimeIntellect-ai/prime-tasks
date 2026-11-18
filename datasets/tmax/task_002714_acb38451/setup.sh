#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import sqlite3
import random
import statistics
import os
import shutil

db_path = "/home/user/sensor.db"

conn = sqlite3.connect(db_path)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, timestamp DATETIME, value REAL)")

random.seed(42)
base_val = 100000000.0
values = [base_val + random.uniform(0, 1) for _ in range(50000)]

conn.executemany("INSERT INTO measurements (timestamp, value) VALUES (datetime('now'), ?)", [(v,) for v in values])
conn.commit()

conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")

more_values = [base_val + random.uniform(0, 1) for _ in range(50000)]
all_values = values + more_values

conn.executemany("INSERT INTO measurements (timestamp, value) VALUES (datetime('now'), ?)", [(v,) for v in more_values])
conn.commit()

true_variance = statistics.variance(all_values)
with open("/tmp/expected_variance.txt", "w") as f:
    f.write(f"{true_variance:.4f}")

shutil.copy(db_path, db_path + ".bak")
shutil.copy(db_path + "-wal", db_path + "-wal.bak")
EOF

python3 /tmp/setup.py

mv /home/user/sensor.db.bak /home/user/sensor.db
mv /home/user/sensor.db-wal.bak /home/user/sensor.db-wal
rm -f /home/user/sensor.db-shm

# Corrupt the main DB header
dd if=/dev/urandom of=/home/user/sensor.db bs=100 count=1 conv=notrunc

chmod -R 777 /home/user
chmod 777 /tmp/expected_variance.txt
