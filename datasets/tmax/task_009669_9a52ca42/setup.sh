#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/billing_processor.py
import json
import sys
from datetime import datetime

def calculate_daily_aggregates(transactions, start_date, end_date):
    start = datetime.strptime(start_date, '%Y-%m-%d')
    end = datetime.strptime(end_date, '%Y-%m-%d')
    days = (end - start).days

    daily_totals = [0] * days

    for tx in transactions:
        tx_date = datetime.strptime(tx['date'], '%Y-%m-%d')
        if start <= tx_date <= end:
            idx = (tx_date - start).days
            daily_totals[idx] += tx['amount']

    return daily_totals

if __name__ == '__main__':
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    try:
        res = calculate_daily_aggregates(data, '2023-10-01', '2023-10-31')
        print(sum(res))
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
EOF

    cat << 'EOF' > /home/user/large_transactions.json
[
    {"id": "tx001", "date": "2023-09-25", "amount": 10.0},
    {"id": "tx002", "date": "2023-10-01", "amount": 5.0},
    {"id": "tx003", "date": "2023-10-15", "amount": 12.0},
    {"id": "tx004", "date": "2023-10-30", "amount": 8.0},
    {"id": "tx005", "date": "2023-10-31", "amount": 25.0},
    {"id": "tx006", "date": "2023-11-01", "amount": 14.0}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
