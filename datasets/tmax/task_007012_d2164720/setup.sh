#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# Generate users
user_ids = np.arange(1, 1001)
ages = np.random.randint(18, 70, size=1000)
ages = np.where(np.random.rand(1000) < 0.05, np.nan, ages) # 5% missing
balances = np.random.uniform(100, 10000, size=1000)
credits = np.random.randint(300, 850, size=1000)

users_df = pd.DataFrame({
    'user_id': user_ids,
    'age': ages,
    'account_balance': balances,
    'credit_score': credits
})
users_df.to_csv('/home/user/data/users.csv', index=False)

# Generate transactions
tx_ids = np.arange(10001, 15001)
tx_user_ids = np.random.choice(user_ids, size=5000)
amounts = np.random.uniform(10, 500, size=5000)
amounts = np.where(np.random.rand(5000) < 0.05, np.nan, amounts) # 5% missing

# Simulate fraud logic (hidden)
is_fraud = ((amounts > 400) & (np.random.rand(5000) < 0.3)).astype(int)

transactions_df = pd.DataFrame({
    'transaction_id': tx_ids,
    'user_id': tx_user_ids,
    'amount': amounts,
    'is_fraud': is_fraud
})
transactions_df.to_csv('/home/user/data/transactions.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
