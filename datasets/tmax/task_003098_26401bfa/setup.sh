#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
#!/usr/bin/env python3
import sqlite3
import random
import os
from PIL import Image, ImageDraw, ImageFont

os.makedirs('/app', exist_ok=True)

# 1. Create the SQLite DB
db_path = '/app/backup_metadata.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE Servers (id TEXT PRIMARY KEY, hostname TEXT)")
c.execute("CREATE TABLE Topology (source_id TEXT, target_id TEXT)")
c.execute("CREATE TABLE Logs (server_id TEXT, ts INTEGER, bytes INTEGER)")

# Populate Servers
servers = [f"srv_{str(i).zfill(3)}" for i in range(1, 21)]
for s in servers:
    c.execute("INSERT INTO Servers VALUES (?, ?)", (s, f"host_{s}"))

# Populate Topology (Graph)
edges = [
    ("srv_001", "srv_002"),
    ("srv_001", "srv_003"),
    ("srv_002", "srv_004"),
    ("srv_002", "srv_005"),
    ("srv_003", "srv_006"),
    # Unrelated cluster
    ("srv_010", "srv_011")
]
c.executemany("INSERT INTO Topology VALUES (?, ?)", edges)

# Populate Logs
random.seed(42)
batch = []
target_servers = ["srv_001", "srv_002", "srv_003", "srv_004", "srv_005", "srv_006"]
total_bytes = 0

for i in range(500000):
    srv = random.choice(servers)
    b = random.randint(1000, 5000)
    batch.append((srv, i, b))
    if srv in target_servers:
        total_bytes += b

c.executemany("INSERT INTO Logs VALUES (?, ?, ?)", batch)
conn.commit()
conn.close()

# Save the target value so verifier knows it
with open('/app/ground_truth.txt', 'w') as f:
    f.write(str(total_bytes))

# 2. Create the Image Fixture
img = Image.new('RGB', (600, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)

text = """
DATABASE SCHEMA RECOVERY DIAGRAM
--------------------------------
Tables:
1. Servers (id, hostname)
2. Topology (source_id, target_id)
3. Logs (server_id, ts, bytes)

Cluster Info:
Master Node ID: srv_001
"""
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/schema_diagram.png')

# Ensure permissions
os.chmod('/app/backup_metadata.db', 0o777)
os.chmod('/app/schema_diagram.png', 0o777)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
