#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data /home/user/src

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate Users
users = pd.DataFrame({
    'user_id': range(1, 1001),
    'age': np.random.normal(40, 15, 1000),
    'location_id': np.random.randint(1, 50, 1000)
})
# Introduce schema errors
users.loc[10:20, 'age'] = np.nan

# Generate Transactions
tx = pd.DataFrame({
    'user_id': np.random.choice(range(1, 1001), 2000),
    'amount': np.random.normal(100, 50, 2000),
    'is_fraud': np.random.choice([0, 1], 2000, p=[0.9, 0.1])
})
# Introduce schema errors
tx.loc[50:60, 'amount'] = -15.5

users.to_csv('/home/user/data/users.csv', index=False)
tx.to_csv('/home/user/data/transactions.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py

    cat << 'EOF' > /home/user/src/train.py
import pandas as pd
import json
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression

def main():
    users = pd.read_csv('/home/user/data/users.csv')
    tx = pd.read_csv('/home/user/data/transactions.csv')
    df = pd.merge(tx, users, on='user_id')

    # BUG: Data Leakage
    scaler = StandardScaler()
    df[['amount', 'age']] = scaler.fit_transform(df[['amount', 'age']])

    X = df[['amount', 'age', 'location_id']]
    y = df['is_fraud']

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    model = LogisticRegression(random_state=42)
    model.fit(X_train, y_train)
    acc = model.score(X_test, y_test)

    with open('/home/user/metrics_fixed.json', 'w') as f:
        json.dump({'accuracy': acc}, f)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
