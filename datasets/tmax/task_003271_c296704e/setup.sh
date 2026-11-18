#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/app/network.db')
c = conn.cursor()
c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, region TEXT, value REAL)")
c.execute("CREATE TABLE edges (source INTEGER, target INTEGER, weight REAL)")

types = ['user', 'admin', 'bot']
regions = ['NA', 'EU', 'AS']

nodes = []
for i in range(1, 5001):
    nodes.append((i, random.choice(types), random.choice(regions), random.uniform(1, 100)))

c.executemany("INSERT INTO nodes VALUES (?, ?, ?, ?)", nodes)

edges = []
for _ in range(25000):
    edges.append((random.randint(1, 5000), random.randint(1, 5000), random.uniform(0.1, 5.0)))

c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py

    # Generate baseline.py
    cat << 'EOF' > /app/baseline.py
import sqlite3, json
conn = sqlite3.connect('/app/network.db')
c = conn.cursor()
regions = {}
for row in c.execute("SELECT id, region, value FROM nodes WHERE type != 'bot' AND value > 10").fetchall():
    node_id, region, val = row
    edges = c.execute("SELECT target, weight FROM edges WHERE source = ?", (node_id,)).fetchall()
    for edge in edges:
        target, weight = edge
        target_val = c.execute("SELECT value FROM nodes WHERE id = ?", (target,)).fetchone()[0]
        regions[region] = regions.get(region, 0) + (weight * target_val)
with open('/app/results.json', 'w') as f:
    json.dump(regions, f)
EOF

    # Generate whiteboard.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,100 'CRITICAL: Target nodes must ALSO have type != \'bot\''" /app/whiteboard.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
