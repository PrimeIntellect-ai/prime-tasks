#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs("/home/user", exist_ok=True)
db_path = "/home/user/locks.db"

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE lock_requests (
    tx_id TEXT,
    resource_id TEXT,
    request_time INTEGER,
    grant_time INTEGER,
    release_time INTEGER
)''')

# Insert data
# Deadlock 1 (Cycle of 2): T1 waits for T2, T2 waits for T1
c.execute("INSERT INTO lock_requests VALUES ('T1', 'R1', 8, 10, NULL)")
c.execute("INSERT INTO lock_requests VALUES ('T2', 'R1', 15, NULL, NULL)")

c.execute("INSERT INTO lock_requests VALUES ('T2', 'R2', 11, 12, NULL)")
c.execute("INSERT INTO lock_requests VALUES ('T1', 'R2', 18, NULL, NULL)")

# Deadlock 2 (Cycle of 3): T3 -> T4 -> T5 -> T3
c.execute("INSERT INTO lock_requests VALUES ('T3', 'R3', 20, 22, NULL)")
c.execute("INSERT INTO lock_requests VALUES ('T4', 'R3', 25, NULL, NULL)")

c.execute("INSERT INTO lock_requests VALUES ('T4', 'R4', 21, 23, NULL)")
c.execute("INSERT INTO lock_requests VALUES ('T5', 'R4', 26, NULL, NULL)")

c.execute("INSERT INTO lock_requests VALUES ('T5', 'R5', 22, 24, NULL)")
c.execute("INSERT INTO lock_requests VALUES ('T3', 'R5', 27, NULL, NULL)")

# Non-deadlocked
c.execute("INSERT INTO lock_requests VALUES ('T6', 'R6', 30, 31, 40)")
c.execute("INSERT INTO lock_requests VALUES ('T7', 'R6', 35, 41, 50)")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
