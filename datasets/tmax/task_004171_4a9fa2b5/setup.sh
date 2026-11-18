#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/users.csv
user_id,age,income
1,25,50000
2,34,60000
3,45,80000
4,23,45000
5,30,55000
6,50,90000
7,28,52000
8,38,65000
9,42,75000
10,21,40000
EOF

cat << 'EOF' > /home/user/interactions.csv
user_id,item_id,rating
1,101,4
1,102,5
2,101,3
3,103,5
4,104,2
5,102,4
6,105,5
7,101,4
8,103,3
9,104,4
10,105,2
EOF

cat << 'EOF' > /home/user/prepare_data.py
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

# Load data
users = pd.read_csv('/home/user/users.csv')
interactions = pd.read_csv('/home/user/interactions.csv')

# Join data
df = pd.merge(interactions, users, on='user_id')

# Data Leak: Scaling before splitting
scaler = StandardScaler()
df[['age', 'income']] = scaler.fit_transform(df[['age', 'income']])

# Split
train, test = train_test_split(df, test_size=0.2, random_state=42)

# Save
train.to_csv('/home/user/train.csv', index=False)
test.to_csv('/home/user/test.csv', index=False)
EOF

chmod -R 777 /home/user
