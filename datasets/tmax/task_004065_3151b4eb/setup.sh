#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the database setup script
    cat << 'EOF' > /tmp/make_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/app/graph.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT)')
c.execute('CREATE TABLE edges (src INTEGER, dst INTEGER, weight REAL)')

types = ['user', 'post', 'comment', 'page']
nodes = [(i, random.choice(types)) for i in range(1, 5001)]
c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)

edges = [(random.randint(1, 5000), random.randint(1, 5000), random.random()) for _ in range(25000)]
c.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    # Create the image setup script
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

text = """Schema:
CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT);
CREATE TABLE edges (src INTEGER, dst INTEGER, weight REAL);

Slow Query:
SELECT a.type, SUM(e1.weight + e2.weight + e3.weight)
FROM nodes a
JOIN edges e1 ON a.id = e1.src
JOIN edges e2 ON e1.dst = e2.src
JOIN edges e3 ON e2.dst = e3.src
WHERE a.type = 'user' AND e3.weight > 0.5
GROUP BY a.type;"""

font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 24)
img = Image.new('RGB', (1000, 500), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/schema_and_query.png')
EOF

    # Execute setup scripts
    python3 /tmp/make_db.py
    python3 /tmp/make_image.py

    # Clean up
    rm /tmp/make_db.py /tmp/make_image.py

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
