#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr
    pip3 install pytest Pillow pytesseract flask fastapi uvicorn networkx requests

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import sqlite3
from PIL import Image, ImageDraw

# DB setup
conn = sqlite3.connect('/app/data.db')
c = conn.cursor()
c.execute("CREATE TABLE clients (id INTEGER PRIMARY KEY, name TEXT);")
c.execute("CREATE TABLE vendors (id INTEGER PRIMARY KEY, name TEXT);")
c.execute("CREATE TABLE sales (id INTEGER PRIMARY KEY, client_id INTEGER, vendor_id INTEGER, status TEXT);")
c.execute("INSERT INTO clients VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');")
c.execute("INSERT INTO vendors VALUES (10, 'TechStore'), (20, 'BookStore');")
c.execute("INSERT INTO sales VALUES (100, 1, 10, 'SUCCESS'), (101, 2, 10, 'SUCCESS'), (102, 1, 10, 'FAILED'), (103, 3, 20, 'SUCCESS'), (104, 3, 20, 'SUCCESS');")
conn.commit()
conn.close()

# Image setup
img = Image.new('RGB', (800, 200), color='white')
d = ImageDraw.Draw(img)
d.text((10,50), "ETL Rule: Exclude sales where status='FAILED'.", fill=(0,0,0))
d.text((10,80), "Graph Metric: Calculate Vendor Degree Centrality", fill=(0,0,0))
d.text((10,110), "(count of unique clients per vendor).", fill=(0,0,0))
img.save('/app/business_rules.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
