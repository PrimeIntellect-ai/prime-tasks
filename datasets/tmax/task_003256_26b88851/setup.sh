#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os
from PIL import Image, ImageDraw

os.makedirs("/app", exist_ok=True)

# Create DB
conn = sqlite3.connect("/app/knowledge.db")
c = conn.cursor()
c.execute("CREATE TABLE edges (source_node TEXT, target_node TEXT, edge_label TEXT, is_deleted INTEGER)")
# Insert sample graph data
data = [
    ("N1", "N2", "KNOWS", 0),
    ("N2", "N3", "KNOWS", 0),
    ("N3", "N4", "KNOWS", 0),
    ("N1", "N5", "KNOWS", 1), # Deleted edge
    ("N5", "N6", "KNOWS", 0),
    ("N1", "N7", "LIKES", 0)
]
c.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", data)
conn.commit()
conn.close()

# Create Image
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
# Using default font for simplicity in generation, tesseract can read it if large enough or we can rely on standard text
d.text((10,10), "OPTIMIZATION HINT: CREATE INDEX idx_edge_opt ON edges(source_node, edge_label); FILTER DELETED: WHERE is_deleted = 0", fill=(0,0,0))
img.save("/app/schema_hint.png")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
