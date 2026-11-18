#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest pandas Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/init.sql
CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE sessions (session_id INTEGER PRIMARY KEY, user_id INTEGER, start_time INTEGER, end_time INTEGER);
CREATE TABLE orders (order_id INTEGER PRIMARY KEY, user_id INTEGER, order_time INTEGER, amount REAL);

INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob');
INSERT INTO sessions VALUES (101, 1, 1000, 2000), (102, 1, 3000, 4000), (103, 2, 1500, 2500);
INSERT INTO orders VALUES (1, 1, 1500, 50.0), (2, 1, 3500, 75.5), (3, 1, 3600, 24.5), (4, 2, 2000, 100.0), (5, 1, 5000, 10.0);
EOF

    sqlite3 /app/data.db < /tmp/init.sql

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (1200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Entity Relationship: Join orders to sessions using orders.user_id = sessions.user_id AND orders.order_time >= sessions.start_time AND orders.order_time <= sessions.end_time"
d.text((10, 40), text, fill=(0, 0, 0))
img.save('/app/schema.png')
EOF

    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
