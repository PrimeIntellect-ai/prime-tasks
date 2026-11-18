#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    python3 -c "
import csv
import random
from PIL import Image, ImageDraw

# Generate Image
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Relationships: users.user_id = orders.user_id | orders.order_id = items.order_id'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/schema_diagram.png')

# Generate CSVs
with open('/app/users.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'user_name'])
    for i in range(1, 50001):
        writer.writerow([i, f'User_{i}'])

with open('/app/orders.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['order_id', 'user_id', 'order_date'])
    for i in range(1, 150001):
        writer.writerow([i, random.randint(1, 50000), '2023-01-01'])

with open('/app/items.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['item_id', 'order_id', 'item_name', 'price'])
    for i in range(1, 500001):
        writer.writerow([i, random.randint(1, 150000), f'Item_{i}', '10.50'])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
