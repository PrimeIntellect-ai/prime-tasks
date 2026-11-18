#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import json

np.random.seed(42)

# Train data
n_train = 50
ids = np.arange(1, n_train + 1)
age = np.random.randint(18, 70, n_train)
income = np.random.uniform(30000, 100000, n_train)
score = np.random.uniform(0, 100, n_train)
# spend is highly correlated with income and score
spend = 0.005 * income + 5.0 * score + np.random.normal(0, 50, n_train)

train_df = pd.DataFrame({'id': ids, 'age': age, 'income': income, 'score': score, 'spend': spend})
# Add bad rows to test schema enforcement
train_df.loc[50] = ['bad_id', 25, 50000, 50, 200]
train_df.loc[51] = [52, 'bad_age', 50000, 50, 200]
train_df.loc[52] = [53, 25, np.nan, 50, 200]

train_df.to_csv('/home/user/train.csv', index=False)

# Test data
n_test = 5
test_ids = np.arange(100, 100 + n_test)
test_age = np.random.randint(18, 70, n_test)
test_income = np.random.uniform(30000, 100000, n_test)
test_score = np.random.uniform(0, 100, n_test)

test_df = pd.DataFrame({'id': test_ids, 'age': test_age, 'income': test_income, 'score': test_score})
test_df.loc[5] = ['bad_id', 25, 50000, 50]
test_df.loc[6] = [105, 30, 'bad_income', 60]

test_df.to_csv('/home/user/test.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
