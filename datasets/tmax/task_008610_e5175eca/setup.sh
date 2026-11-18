#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/scripts
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/january_usage.json
{
  "items": [
    {"id": "item1", "price": 100.0, "qty": 2, "discount_pct": 10},
    {"id": "item2", "price": 50.0, "qty": 1, "discount_pct": 0},
    {"id": "item3", "price": 200.0, "qty": 3, "discount_pct": 5}
  ]
}
EOF

    cat << 'EOF' > /home/user/scripts/calc_billing.py
import sys
import json

def calculate_bill(data_file):
    with open(data_file, 'r') as f:
        data = json.load(f)

    total_bill = 0.0
    # Bug 1: off-by-one skips the first element (index 0)
    for i in range(1, len(data['items'])):
        item = data['items'][i]
        base_price = item['price']
        qty = item['qty']
        discount = item['discount_pct'] / 100.0

        # Bug 2: Formula error computes the discount, not the discounted price
        cost = (base_price * qty) * discount

        total_bill += cost

    return round(total_bill, 2)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(calculate_bill(sys.argv[1]))
EOF

    # Create an environment script to start the tail process and delete the file at runtime
    cat << 'EOF' > /.singularity.d/env/99-setup.sh
if [ -f /home/user/scripts/calc_billing.py ]; then
    tail -f /home/user/scripts/calc_billing.py > /dev/null 2>&1 &
    sleep 0.5
    rm -f /home/user/scripts/calc_billing.py
fi
EOF
    chmod +x /.singularity.d/env/99-setup.sh

    chmod -R 777 /home/user
