#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn pyarrow

    mkdir -p /home/user/fraud_project/data
    cd /home/user/fraud_project

    cat << 'EOF' > data/users.csv
user_id,age,credit_score
1,25,600
2,45,750
3,32,680
4,50,800
5,22,550
6,38,710
7,29,640
8,41,720
9,55,810
10,27,590
11,33,660
12,48,770
13,24,580
14,36,690
15,30,650
16,42,730
17,52,790
18,28,620
19,35,670
20,46,760
EOF

    cat << 'EOF' > data/transactions.csv
user_id,amount
1,100
1,50
2,1000
3,200
3,300
4,1500
5,20
6,500
7,150
8,800
9,2000
10,80
11,250
12,1200
13,60
14,400
15,180
16,900
17,1700
18,120
19,350
20,1100
EOF

    cat << 'EOF' > data/labels.csv
user_id,is_fraud
1,1
2,0
3,0
4,0
5,1
6,0
7,0
8,0
9,0
10,1
11,0
12,0
13,1
14,0
15,0
16,0
17,0
18,1
19,0
20,0
EOF

    cat << 'EOF' > train_model.py
import pandas as pd
import numpy as np
import json
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

# Load data
users = pd.read_csv('data/users.csv')
tx = pd.read_csv('data/transactions.csv')
labels = pd.read_csv('data/labels.csv')

# Aggregate transactions
tx_agg = tx.groupby('user_id')['amount'].sum().reset_index()

# Join data
df = users.merge(tx_agg, on='user_id', how='left').merge(labels, on='user_id', how='left')
df['amount'] = df['amount'].fillna(0)

X = df[['age', 'credit_score', 'amount']]
y = df['is_fraud']

# DANGER: Data Leakage
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

preds = model.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, preds)

print(f"ROC AUC: {auc}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
