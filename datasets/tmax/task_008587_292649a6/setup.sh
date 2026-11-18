#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/raw_data/transactions.csv
txn_id,customer_id,transaction_value
1,101,50.5
2,,20.0
3,102,150.75
4,101,300.0
EOF

    cat << 'EOF' > /home/user/raw_data/customers.csv
customer_id,customer_name,region
101,Alice,North
102,Bob,South
103,Charlie,East
EOF

    cat << 'EOF' > /home/user/process_data.py
import pandas as pd
import numpy as np
import os

def main():
    os.makedirs('/home/user/artifacts', exist_ok=True)

    # Read data
    txns = pd.read_csv('/home/user/raw_data/transactions.csv')
    custs = pd.read_csv('/home/user/raw_data/customers.csv')

    # Merge introduces NaNs for txn_id 2, casting customer_id to float
    merged = pd.merge(txns, custs, on='customer_id', how='left')

    # (Agent needs to fix the NaN issue here, cast to int, and add log_transaction_value)

    merged.to_csv('/home/user/artifacts/processed_data.csv', index=False)

    # (Agent needs to add schema.json export)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
