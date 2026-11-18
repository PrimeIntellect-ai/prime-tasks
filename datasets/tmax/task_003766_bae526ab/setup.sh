#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

# Generate users.csv
users = []
for i in range(1, 1001):
    status = 'ACTIVE' if random.random() > 0.2 else 'INACTIVE'
    users.append([i, f'User_{i}', status])

with open('/home/user/users.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'name', 'status'])
    writer.writerows(users)

# Generate transactions.csv
start_date = datetime(2022, 1, 1)
transactions = []
for i in range(1, 10001):
    user_id = random.randint(1, 1000)
    amount = round(random.uniform(10.0, 500.0), 2)
    days_offset = random.randint(0, 730)
    tx_date = (start_date + timedelta(days=days_offset)).strftime('%Y-%m-%d')
    transactions.append([i, user_id, amount, tx_date])

with open('/home/user/transactions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['tx_id', 'user_id', 'amount', 'tx_date'])
    writer.writerows(transactions)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
