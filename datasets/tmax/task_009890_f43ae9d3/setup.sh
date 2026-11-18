#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data /home/user/config

    cat << 'EOF' > /tmp/generate_data.py
import os
import json
import csv
import random

os.makedirs("/home/user/raw_data", exist_ok=True)
os.makedirs("/home/user/config", exist_ok=True)

rates = {
    "USD": 1.0,
    "EUR": 1.1,
    "GBP": 1.25,
    "JPY": 0.007,
    "CAD": 0.75
}

with open("/home/user/config/exchange_rates.json", "w") as f:
    json.dump(rates, f)

categories = ["Electronics", "Clothing", "Home", "Sports", "Books"]
random.seed(42)

# Generate CSVs
order_id = 1
for chunk in range(20):
    with open(f"/home/user/raw_data/sales_chunk_{chunk}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["order_id", "timestamp", "category", "price", "quantity", "currency"])
        for _ in range(500):
            cat = random.choice(categories)
            price = round(random.uniform(5.0, 500.0), 2)
            qty = random.randint(1, 10)
            curr = random.choice(list(rates.keys()))
            writer.writerow([f"ORD{order_id:05d}", "2023-10-01T12:00:00Z", cat, price, qty, curr])
            order_id += 1
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
