#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user

    python3 -c "
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic data
np.random.seed(10)
n_users = 1000

user_ids = np.arange(1, n_users + 1)
ages = np.random.randint(18, 70, size=n_users)
churn = np.random.binomial(1, 0.3, size=n_users)

users_df = pd.DataFrame({'user_id': user_ids, 'age': ages, 'churn': churn})
users_df.to_csv('/home/user/users.csv', index=False)

# Generate transactions
n_tx = 5000
tx_user_ids = np.random.choice(user_ids, size=n_tx)
amounts = np.random.exponential(50, size=n_tx)

tx_df = pd.DataFrame({'user_id': tx_user_ids, 'amount': amounts})
tx_df.to_csv('/home/user/transactions.csv', index=False)

# Create buggy train_model.py
buggy_script = \"\"\"import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

# Load data
users = pd.read_csv('/home/user/users.csv')
tx = pd.read_csv('/home/user/transactions.csv')

# Aggregate transactions
tx_agg = tx.groupby('user_id')['amount'].sum().reset_index()

# Join
df = pd.merge(users, tx_agg, on='user_id', how='left').fillna(0)

X = df[['age', 'amount']]
y = df['churn']

# BUG: Data leakage
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)
print(f\"Accuracy: {accuracy}\")
\"\"\"
with open('/home/user/train_model.py', 'w') as f:
    f.write(buggy_script)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
