#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr fonts-dejavu
    pip3 install pytest pillow

    mkdir -p /app
    sqlite3 /app/backup.sqlite <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER);
INSERT INTO nodes VALUES (1, 'Server', 'web01'), (2, 'Server', 'web02'), (3, 'LoadBalancer', 'lb01'), (4, 'Database', 'db01'), (5, 'Database', 'db02');
INSERT INTO edges VALUES (1, 3), (3, 4), (2, 5);
CREATE INDEX idx_edges_source ON edges(source);
CREATE INDEX idx_edges_target ON edges(target);
EOF

    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (800, 100), color="white")
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
d.text((20, 40), "TARGET: Server -> LoadBalancer -> Database", fill="black", font=font)
img.save("/app/pattern.png")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
