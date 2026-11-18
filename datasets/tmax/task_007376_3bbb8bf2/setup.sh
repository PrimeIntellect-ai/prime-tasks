#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = '/home/user/etl_lineage.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE dependencies (
    id INTEGER PRIMARY KEY,
    source_task INTEGER,
    target_task INTEGER,
    transfer_cost INTEGER
)''')

random.seed(42)
edges = []

# Create a guaranteed path from 0 to 9999 with cost 40
current = 0
path_nodes = [0, 2500, 5000, 7500, 9999]
for i in range(len(path_nodes)-1):
    edges.append((path_nodes[i], path_nodes[i+1], 10)) # Total cost = 40

# Add random noise edges
for i in range(15000):
    src = random.randint(0, 9998)
    tgt = random.randint(src + 1, 9999)
    cost = random.randint(15, 100)
    edges.append((src, tgt, cost))

c.executemany('INSERT INTO dependencies (source_task, target_task, transfer_cost) VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
