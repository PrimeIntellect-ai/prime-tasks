#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate 1000 users
users = pd.DataFrame({
    'user_id': range(1, 1001),
    'age': np.random.randint(18, 70, size=1000)
})

# Generate transactions for 700 users
tx_users = np.random.choice(range(1, 1001), size=700, replace=False)
transactions = pd.DataFrame({
    'user_id': tx_users,
    'store_id': np.random.randint(1, 10, size=700),
    'amount': np.round(np.random.uniform(10.0, 500.0, size=700), 2)
})

# Generate labels based on a hidden rule
# Higher age and no transaction -> more likely to churn
churn_prob = np.zeros(1000)
for i, row in users.iterrows():
    prob = 0.1
    if row['age'] > 50:
        prob += 0.3
    if row['user_id'] not in tx_users:
        prob += 0.4
    churn_prob[i] = prob

churned = np.random.binomial(1, churn_prob)
labels = pd.DataFrame({
    'user_id': users['user_id'],
    'churned': churned
})

users.to_csv('/home/user/data/users.csv', index=False)
transactions.to_csv('/home/user/data/transactions.csv', index=False)
labels.to_csv('/home/user/data/labels.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
