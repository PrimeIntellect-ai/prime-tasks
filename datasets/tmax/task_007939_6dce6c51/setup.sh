#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest python-dateutil requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/exchange_rates.json
{
    "USD": 1.0,
    "EUR": 1.1,
    "GBP": 1.25,
    "JPY": 0.007
}
EOF

    cat << 'EOF' > /home/user/create_csv.py
import csv

data = [
    {"timestamp": "01/15/2023 14:30:00", "email": " ALICE@Example.com ", "amount": "100.00", "currency": "USD"},
    {"timestamp": "2023-01-15T18:45:00Z", "email": "bob@test.org", "amount": "50.00", "currency": "EUR"},
    {"timestamp": "16-01-2023 09:15", "email": "  ", "amount": "200.0", "currency": "GBP"},
    {"timestamp": "01/16/2023 11:00:00", "email": "CAROL@domain.net", "amount": "10000", "currency": "JPY"},
    {"timestamp": "2023-01-16T22:10:00Z", "email": "dave@example.com", "amount": "75.00", "currency": "AUD"},
    {"timestamp": "01/17/2023 08:00:00", "email": "eve@domain.com", "amount": "150.00", "currency": "GBP"}
]

with open('/home/user/transactions.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "email", "amount", "currency"])
    writer.writeheader()
    writer.writerows(data)
EOF

    python3 /home/user/create_csv.py
    rm /home/user/create_csv.py

    chmod -R 777 /home/user
