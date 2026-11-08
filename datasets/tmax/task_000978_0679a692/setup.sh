#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate users
users = pd.DataFrame({
    'user_id': range(1, 101),
    'age': np.random.randint(18, 65, size=100),
    'target': np.random.randint(0, 2, size=100)
})

# Generate transactions (only for some users)
tx_users = np.random.choice(range(1, 101), size=70, replace=False)
transactions = pd.DataFrame({
    'user_id': tx_users,
    'amount': np.random.uniform(10.0, 500.0, size=70).round(2),
    'group_id': np.random.randint(1, 10, size=70) # strictly integers
})

users.to_csv('/home/user/data/users.csv', index=False)
transactions.to_csv('/home/user/data/transactions.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
