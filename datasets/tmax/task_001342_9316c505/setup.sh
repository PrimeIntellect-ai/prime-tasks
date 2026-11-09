#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the image using Python Pillow
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (1000, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Join raw_links and link_costs on link_id. Compute shortest path from node 1050 to node 8920."
d.text((10, 50), text, fill=(0, 0, 0))
img.save('/app/schema.png')
EOF
    python3 /tmp/make_image.py

    # Generate the database
    cat << 'EOF' > /tmp/make_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/network.db')
c = conn.cursor()
c.execute("CREATE TABLE raw_links (link_id INTEGER PRIMARY KEY, source INTEGER, target INTEGER)")
c.execute("CREATE TABLE link_costs (link_id INTEGER PRIMARY KEY, cost INTEGER)")

path_edges = [
    (1, 1050, 2000, 50),
    (2, 2000, 3000, 50),
    (3, 3000, 8920, 42)
]

for e in path_edges:
    c.execute("INSERT INTO raw_links VALUES (?, ?, ?)", (e[0], e[1], e[2]))
    c.execute("INSERT INTO link_costs VALUES (?, ?)", (e[0], e[3]))

# Insert random edges with cost > 150 to ensure the shortest path is exactly 142
for i in range(4, 50000):
    u = random.randint(1, 10000)
    v = random.randint(1, 10000)
    cost = random.randint(150, 1000)
    c.execute("INSERT INTO raw_links VALUES (?, ?, ?)", (i, u, v))
    c.execute("INSERT INTO link_costs VALUES (?, ?)", (i, cost))

conn.commit()
conn.close()
EOF
    python3 /tmp/make_db.py

    # Create the slow reference script
    cat << 'EOF' > /app/ref_slow.py
import sqlite3
import time

conn = sqlite3.connect('/app/network.db')
c = conn.cursor()

# Slow query
c.execute("SELECT r.source, r.target, c.cost FROM raw_links r JOIN link_costs c ON r.link_id = c.link_id")
edges = c.fetchall()

# Artificial delay to simulate an unoptimized implementation and ensure 5x speedup is possible
time.sleep(2.0)

dist = {1050: 0}
for _ in range(5):
    for u, v, cost in edges:
        if u in dist:
            if v not in dist or dist[u] + cost < dist[v]:
                dist[v] = dist[u] + cost

print(dist.get(8920, -1))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
