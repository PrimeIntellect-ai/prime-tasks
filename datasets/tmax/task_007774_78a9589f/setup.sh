#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/billing_logs.txt
txn_id=101 Amount="10.10"
txn_id=102 Amount="20.20"
txn_id=103 Amount="30.30"
txn_id=104 Amount="1,000.05"
txn_id=105 Amount="N/A"
txn_id=106 Amount=""
txn_id=107 Amount="0.10"
txn_id=108 Amount="0.20"
EOF

    cat << 'EOF' > /home/user/aggregate_billing.py
def parse_amount(line):
    try:
        # Extract the amount value inside the quotes
        parts = line.split('Amount="')
        if len(parts) > 1:
            val_str = parts[1].split('"')[0]
            return float(val_str)
        return 0.0
    except ValueError:
        return 0.0

def aggregate_logs(filepath):
    total = 0.0
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            total += parse_amount(line)
    return total

if __name__ == "__main__":
    total = aggregate_logs("/home/user/billing_logs.txt")
    print(total)
EOF

    chmod -R 777 /home/user
