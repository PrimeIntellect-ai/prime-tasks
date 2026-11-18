#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc
    pip3 install pytest pandas Pillow

    mkdir -p /app

    # Generate receipt image
    cat << 'EOF' > /app/generate_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "TAX_REGION: TX-882-A", fill=(0, 0, 0))
img.save('/app/receipt_sample.png')
EOF
    python3 /app/generate_img.py
    rm /app/generate_img.py

    # Create transactions.jsonl
    cat << 'EOF' > /app/transactions.jsonl
{"merchant_id": "M123", "txn_1_amt": 15.50, "txn_1_desc": "Coffee shop [Region: TX-882-A]", "txn_2_amt": 12.00, "txn_2_desc": "Muffins [Region: R-99]"}
{"merchant_id": "M123", "txn_1_amt": 5.00, "txn_1_desc": "Tea \\u0026 cake [Region: TX-882-A]"}
{"merchant_id": "M456", "txn_1_amt": 100.00, "txn_1_desc": "Supplies [Region: TX-882-A]", "txn_2_amt": 50.00, "txn_2_desc": "More supplies [Region: TX-882-A]"}
EOF

    # Create truth_summary.csv
    cat << 'EOF' > /app/truth_summary.csv
merchant_id,total_amount
M123,20.50
M456,150.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
