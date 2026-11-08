#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(123)
with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['marketing_spend', 'website_visits', 'actual_sales'])
    for _ in range(100):
        spend = random.uniform(10, 100)
        visits = random.uniform(100, 500)
        # Add some noise to the actual formula
        noise = random.gauss(0, 15)
        sales = 2.5 * spend + 1.2 * visits + 10.0 + noise
        writer.writerow([round(spend, 2), round(visits, 2), round(sales, 2)])
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
