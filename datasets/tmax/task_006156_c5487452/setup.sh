#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.wal
TXN_001,1500.0,0.5;0.5,0.8
TXN_002,2000.0,0.5;0.5,1.0
TXN_003,1000.0,0.1;0.1;0.1,0.3
TXN_004,3000.0,0.2;0.4,0.1
EOF

    cat << 'EOF' > /home/user/aggregate.py
import sys
import json

def process_wal(filepath):
    results = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split(',')
            txn_id = parts[0]
            amount = float(parts[1])
            components = [float(x) for x in parts[2].split(';')]
            discount = float(parts[3])

            base_rate = sum(components)
            denominator = base_rate - discount

            # Flawed check: vulnerable to floating-point precision issues
            if denominator == 0.0:
                results[txn_id] = "SKIPPED_ZERO"
                continue

            ratio = amount / denominator

            if abs(ratio) > 1000000:
                raise ValueError(f"Sanity check failed for {txn_id}: anomalous ratio {ratio}")

            results[txn_id] = round(ratio, 4)
    return results

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python aggregate.py <wal_file>")
        sys.exit(1)
    data = process_wal(sys.argv[1])
    with open("/home/user/report.json", "w") as f:
        json.dump(data, f, indent=4)
EOF

    chmod +x /home/user/aggregate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
