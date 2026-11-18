#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import json

data = [
    {"product_id": "A1B2C3D4", "price": "$15.50", "category": "electronics", "original_price": 20.00},
    {"product_id": "X9Y8Z7", "price": "10.00", "category": "toys"},
    {"product_id": "B2C3D4E5", "price": "free", "category": "home"},
    {"product_id": "C3D4E5F6", "price": "45.00 USD", "category": "sports", "original_price": 45.00},
    {"product_id": "D4E5F6G7", "price": 120, "category": "clothing"},
    {"product_id": "E5F6G7H8", "price": "-5.00", "category": "toys"},
    {"product_id": "F6G7H8I9", "price": "20.0", "category": "toys", "original_price": "invalid"},
    {"product_id": "G7H8I9J0", "price": "19.99"},
    {"product_id": "H8I9J0K1", "price": "50.00", "category": "home", "original_price": 60.00}
]

with open("/home/user/raw_products.jsonl", "w") as f:
    for item in data:
        f.write(json.dumps(item) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
