#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas pillow

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
from PIL import Image, ImageDraw

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/app', exist_ok=True)

# Generate CSVs
customers = pd.DataFrame({
    'customer_id': [1, 2, 3],
    'name': ['Alice', 'Bob', 'Charlie'],
    'join_date': ['2023-01-15', '2023-05-20', '2023-11-01']
})
customers.to_csv('/home/user/data/customers.csv', index=False)

orders = pd.DataFrame({
    'order_id': [101, 102, 103, 104],
    'customer_id': [1, 1, 2, 3],
    'order_date': ['2023-02-10', '2023-06-15', '2023-08-22', '2023-12-05'],
    'total_amount': [250.50, 120.00, 500.00, 50.00]
})
orders.to_csv('/home/user/data/orders.csv', index=False)

# Generate Image
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "To calculate the customer_value_score:\nscore = (total_spent * 0.65) + (order_count * 15) - (days_since_last_order * 0.25)"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/business_rules.png')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
