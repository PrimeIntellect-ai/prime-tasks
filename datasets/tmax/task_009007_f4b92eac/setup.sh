#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import json

data = []
# Generate 100 predictable records
for i in range(100):
    if i % 2 == 0:
        desc = "High performance laptop with fast processor, great battery life, and vivid screen. Features wifi connectivity."
        cat = "Electronics"
    else:
        desc = "Comfortable cotton t-shirt in standard size. Soft fabric, perfect for casual wear and outdoor activities."
        cat = "Clothing"

    data.append({
        "id": i,
        "description": desc,
        "category": cat
    })

with open("/home/user/data/raw_products.jsonl", "w") as f:
    for row in data:
        f.write(json.dumps(row) + "\n")
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
