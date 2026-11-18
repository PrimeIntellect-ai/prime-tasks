#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/deadlocks.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE wait_graph(src_tx TEXT, dst_tx TEXT, wait_time_ms INTEGER)")

data = [
    ("T1", "T2", 100), ("T2", "T3", 200), ("T3", "T1", 300),
    ("T1", "T4", 150), ("T4", "T5", 150), ("T5", "T1", 400),
    ("T1", "T6", 500), ("T6", "T7", 500), ("T7", "T1", 500),
    ("T1", "T8", 100), ("T8", "T9", 100), ("T9", "T1", 100),
    ("T2", "T4", 200), ("T4", "T1", 300),
    ("T2", "T9", 50), ("T9", "T1", 60),
    ("T5", "T6", 70), ("T6", "T1", 80)
]

c.executemany("INSERT INTO wait_graph VALUES (?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
