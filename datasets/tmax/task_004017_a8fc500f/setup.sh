#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        sqlite3 \
        fonts-dejavu-core

    pip3 install pytest pillow

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Generate the network graph image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont

text = """NodeA 15 NodeB
NodeA 40 NodeC
NodeB 20 NodeD
NodeC 10 NodeD
NodeD 5 NodeE
NodeE 25 NodeF
NodeC 30 NodeF"""

# Create a white image
img = Image.new('RGB', (400, 300), color='white')
d = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 20)
except IOError:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/network_latencies.png')
EOF
    python3 /tmp/gen_image.py

    # Generate the SQLite database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()
c.execute('CREATE TABLE backup_catalog (id INTEGER PRIMARY KEY, node TEXT, timestamp INTEGER, is_full INTEGER, size_bytes INTEGER)')

nodes = ['NodeA', 'NodeB', 'NodeC', 'NodeD', 'NodeE', 'NodeF']
batch_size = 100000

# Insert 2 million rows in batches
for _ in range(20):
    rows = []
    for _ in range(batch_size):
        node = random.choice(nodes)
        ts = random.randint(1500000000, 1690000000)
        is_full = 0
        size = random.randint(1000, 100000)
        rows.append((node, ts, is_full, size))
    c.executemany('INSERT INTO backup_catalog (node, timestamp, is_full, size_bytes) VALUES (?, ?, ?, ?)', rows)

# Insert the specific target row
c.execute('INSERT INTO backup_catalog (node, timestamp, is_full, size_bytes) VALUES (?, ?, ?, ?)', ('NodeA', 1700000000, 1, 5000000))

conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py

    chmod -R 777 /home/user
    chmod -R 777 /app
