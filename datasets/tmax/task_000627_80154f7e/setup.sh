#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3 tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate schema.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''Table 1: 'users'. Join key: 'id'. JSON column: 'profile' (contains 'email'). 
Table 2: 'orders'. Join key: 'user_id'. JSON column: 'items' (array of objects with 'price' and 'qty').
Output Schema: { \"email\": \"...\", \"total_spent\": ... }'''
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/schema.png')
"

    # Create /home/user/data.db
    python3 -c "
import sqlite3
conn = sqlite3.connect('/home/user/data.db')
c = conn.cursor()
c.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY, profile TEXT)''')
c.execute('''CREATE TABLE orders (order_id INTEGER PRIMARY KEY, user_id INTEGER, items TEXT)''')
c.execute('''INSERT INTO users (id, profile) VALUES (101, '{\"email\": \"alice@example.com\"}')''')
c.execute('''INSERT INTO orders (order_id, user_id, items) VALUES (1, 101, '[{\"price\": 10.5, \"qty\": 2}, {\"price\": 5.0, \"qty\": 1}]')''')
conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
