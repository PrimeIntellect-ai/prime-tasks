#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/etl_metadata.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE jobs (id INTEGER PRIMARY KEY, name TEXT, base_cost INTEGER)''')
c.execute('''CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER)''')

jobs = [
    (1, 'extract_sales_data', 10),
    (2, 'clean_sales_data', 20),
    (3, 'aggregate_daily', 30),
    (4, 'join_customer_data', 40),
    (5, 'build_dashboard', 50),
    (6, 'update_ml_model', 100),
    (7, 'unrelated_job', 500)
]

deps = [
    (1, 2),
    (2, 3),
    (2, 4),
    (3, 5),
    (4, 5),
    (4, 6)
]

c.executemany("INSERT INTO jobs VALUES (?, ?, ?)", jobs)
c.executemany("INSERT INTO dependencies VALUES (?, ?)", deps)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
