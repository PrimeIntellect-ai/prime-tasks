#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        cargo \
        rustc \
        curl \
        build-essential \
        pkg-config \
        libssl-dev

    pip3 install pytest pandas Pillow

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)

employees = pd.DataFrame({
    'emp_id': ['E1', 'E2', 'E3', 'E4', 'E5', 'E6'],
    'manager_id': ['', 'E1', 'E1', 'E2', 'E2', 'E3'],
    'dept_id': ['D1', 'D1', 'D1', 'D1', 'D2', 'D1'],
    'name': ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve', 'Frank']
})
employees.to_csv('/app/employees.csv', index=False)

transactions = pd.DataFrame({
    'tx_id': ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'],
    'emp_id': ['E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E6'],
    'amount': [50.0, 200.0, 150.0, 300.0, 400.0, 500.0, 90.0],
    'timestamp': ['2023-01-01']*7
})
transactions.to_csv('/app/transactions.csv', index=False)

img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "API_TOKEN=SuperSecret123!", fill=(0, 0, 0))
d.text((10, 50), "MIN_TX_THRESHOLD=100.0", fill=(0, 0, 0))
img.save('/app/system_config.png')
EOF

    python3 /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app-service
    chmod -R 777 /home/user
    chmod -R 777 /app
