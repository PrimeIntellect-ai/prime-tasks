#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import random
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/backup_catalog.db'

if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''
CREATE TABLE backups (
    backup_id TEXT PRIMARY KEY,
    parent_id TEXT,
    backup_type TEXT,
    status TEXT,
    size_bytes INTEGER
)
''')

# Generate some reproducible data
random.seed(42)
records = []

# Create 50 full backups
full_backups = []
for i in range(1, 51):
    bid = f"full_{i}"
    status = 'success' if random.random() > 0.1 else 'failed'
    size = random.randint(1000000, 5000000)
    records.append((bid, None, 'full', status, size))
    if status == 'success':
        full_backups.append(bid)

# Create incrementals
current_parents = list(full_backups)
for depth in range(1, 10):
    next_parents = []
    for parent in current_parents:
        # 0 to 3 incrementals per parent
        for j in range(random.randint(0, 3)):
            bid = f"inc_{depth}_{parent}_{j}"
            status = 'success' if random.random() > 0.15 else 'failed'
            size = random.randint(10000, 500000)
            records.append((bid, parent, 'incremental', status, size))
            next_parents.append(bid)
    current_parents = next_parents

cur.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?)', records)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py

    chmod -R 777 /home/user
