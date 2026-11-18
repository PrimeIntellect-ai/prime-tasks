#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()

c.execute("CREATE TABLE jobs (id INTEGER PRIMARY KEY, status TEXT, size_mb INTEGER)")
c.execute("CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER)")

jobs_data = [
    (1, 'SUCCESS', 100),
    (2, 'SUCCESS', 50),
    (3, 'SUCCESS', 200),
    (4, 'FAILED', 10),
    (5, 'SUCCESS', 80),
    (6, 'SUCCESS', 30),
    (7, 'SUCCESS', 40),
    (8, 'SUCCESS', 20),
    (9, 'SUCCESS', 70)  # Unreachable from 1
]
c.executemany("INSERT INTO jobs VALUES (?, ?, ?)", jobs_data)

deps_data = [
    (1, 2),
    (1, 3),
    (2, 4),
    (3, 5),
    (4, 6),
    (5, 7),
    (6, 8),
    (8, 4)  # Cycle: 4 -> 6 -> 8 -> 4
]
c.executemany("INSERT INTO dependencies VALUES (?, ?)", deps_data)

conn.commit()
conn.close()
EOF
python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
