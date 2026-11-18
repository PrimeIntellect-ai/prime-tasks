#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,age
1,25
2,30
3,22
4,35
5,28
6,40
7,26
8,33
9,21
10,29
EOF

    cat << 'EOF' > /home/user/purchases.csv
user_id,amount
1,100
2,150
4,200
5,50
6,300
8,120
9,80
10,250
EOF

    cat << 'EOF' > /home/user/prepare_data.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

# Load data
users = pd.read_csv('/home/user/users.csv')
purchases = pd.read_csv('/home/user/purchases.csv')

# Join data
df = pd.merge(users, purchases, on='user_id', how='left')
df['amount'] = df['amount'].fillna(0)

# DATA LEAK: Scaling before splitting!
scaler = StandardScaler()
df['amount'] = scaler.fit_transform(df[['amount']])

# Split data
train, test = train_test_split(df, test_size=0.2, random_state=42)

# Write test mean to file
with open('/home/user/buggy_mean.txt', 'w') as f:
    f.write(str(round(test['amount'].mean(), 4)))
EOF

    chmod -R 777 /home/user
