#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /tmp/setup_data.py
import os
import json
import pandas as pd
import numpy as np

os.makedirs('/home/user/raw_data', exist_ok=True)

# Generate transactions
transactions = pd.DataFrame({
    'txn_id': [f't{i}' for i in range(1, 11)],
    'user_id': ['u1', 'u2', 'u3', 'u4', 'u1', 'u5', 'u6', 'u7', 'u8', 'u9'],
    'revenue': [150.5, 5500.0, -10.0, 200.0, 300.0, 50.0, 450.0, 100.0, 20.0, 5.0]
})
transactions.to_csv('/home/user/raw_data/transactions.csv', index=False)

# Generate queries
queries = [
    {"user_id": "u1", "user_query": "cheap shoes"},
    {"user_id": "u2", "user_query": "luxury watch"},
    {"user_id": "u3", "user_query": "refund"},
    {"user_id": "u4", "user_query": None},
    {"user_id": "u5", "user_query": "discount code"},
    {"user_id": "u6", "user_query": "running shoes"},
    {"user_id": "u7", "user_query": "socks"},
    {"user_id": "u8", "user_query": "hat"},
    {"user_id": "u9", "user_query": "gloves"}
]
with open('/home/user/raw_data/queries.json', 'w') as f:
    json.dump(queries, f)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
