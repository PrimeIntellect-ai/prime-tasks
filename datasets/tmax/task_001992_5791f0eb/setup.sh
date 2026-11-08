#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random

db_path = '/home/user/dependency_graph.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE edges (source INTEGER, target INTEGER)''')
c.execute('''CREATE TABLE node_metrics (node_id INTEGER PRIMARY KEY, category TEXT, score REAL)''')

# Populate metrics
categories = ['A', 'B', 'C', 'D']
for i in range(1, 1001):
    c.execute("INSERT INTO node_metrics (node_id, category, score) VALUES (?, ?, ?)", 
              (i, random.choice(categories), round(random.uniform(10.0, 99.9), 2)))

# Ensure deterministic output for node 100 targets
targets_for_100 = [250, 310, 405, 800, 912]
c.execute("UPDATE node_metrics SET category='A', score=95.0 WHERE node_id=250")
c.execute("UPDATE node_metrics SET category='A', score=98.0 WHERE node_id=310")
c.execute("UPDATE node_metrics SET category='B', score=50.0 WHERE node_id=405")
c.execute("UPDATE node_metrics SET category='B', score=60.0 WHERE node_id=800")
c.execute("UPDATE node_metrics SET category='C', score=88.0 WHERE node_id=912")

for t in targets_for_100:
    c.execute("INSERT INTO edges (source, target) VALUES (?, ?)", (100, t))

# Add some noise edges
for _ in range(5000):
    c.execute("INSERT INTO edges (source, target) VALUES (?, ?)", 
              (random.randint(1, 99), random.randint(1, 1000)))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
