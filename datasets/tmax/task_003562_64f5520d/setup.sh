#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app
    mkdir -p /home/user/raw_data

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = '''Fixing SQLite Deadlocks:
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

Index Strategy:
CREATE INDEX idx_cust_date ON orders(customer_id, order_date DESC);
CREATE INDEX idx_cust_amount ON orders(customer_id, amount);

Target Speed: < 2.0s for 2000 concurrent queries.'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/system_design.png')
"

    python3 -c "
import csv
import random
from datetime import datetime, timedelta
with open('/home/user/raw_data/orders.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['order_id', 'customer_id', 'amount', 'order_date'])
    for i in range(100000):
        writer.writerow([
            f'ORD_{i}',
            f'CUST_{random.randint(1, 100):03d}',
            round(random.uniform(10.0, 500.0), 2),
            (datetime(2023, 1, 1) + timedelta(days=random.randint(0, 365))).strftime('%Y-%m-%d %H:%M:%S')
        ])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
