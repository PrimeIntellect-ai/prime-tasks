#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(123)

# Generate Train Data
n_train = 200
train_ids = np.arange(1, n_train + 1)
f1_train = np.random.randn(n_train)
f2_train = np.random.poisson(lam=3, size=n_train).astype(float)
# Introduce NaNs in f2
f2_train[np.random.choice(n_train, 30, replace=False)] = np.nan
f3_train = np.random.uniform(0, 1, n_train)

# Target is some combination
target_train = ((f1_train + f2_train/2 + f3_train) > 1.5).astype(int)

train_df = pd.DataFrame({
    'id': train_ids,
    'f1': f1_train,
    'f2': f2_train,
    'f3': f3_train,
    'target': target_train
})
train_df.to_csv('/home/user/train.csv', index=False)

# Generate Test Data
n_test = 50
test_ids = np.arange(n_train + 1, n_train + n_test + 1)
f1_test = np.random.randn(n_test)
f2_test = np.random.poisson(lam=3, size=n_test).astype(float)
f2_test[np.random.choice(n_test, 10, replace=False)] = np.nan
f3_test = np.random.uniform(0, 1, n_test)

test_df = pd.DataFrame({
    'id': test_ids,
    'f1': f1_test,
    'f2': f2_test,
    'f3': f3_test
})
test_df.to_csv('/home/user/test.csv', index=False)

# Create Buggy Pipeline Script
buggy_script = """import pandas as pd
from sklearn.ensemble import RandomForestClassifier

# Load data
train = pd.read_csv('/home/user/train.csv')
test = pd.read_csv('/home/user/test.csv')

# Combine to impute (Causes data leakage!)
combined = pd.concat([train, test], ignore_index=True)

# Fill NaNs globally - this silently converts integer columns to float if not careful!
combined.fillna(combined.median(), inplace=True)

# Split back
train_clean = combined[combined['target'].notnull()]
test_clean = combined[combined['target'].isnull()].copy()

X_train = train_clean[['f1', 'f2', 'f3']]
y_train = train_clean['target']
X_test = test_clean[['f1', 'f2', 'f3']]

# Train model without random state (not reproducible)
clf = RandomForestClassifier(n_estimators=50)
clf.fit(X_train, y_train)

# Predict
test_clean['target'] = clf.predict(X_test)

# Save
test_clean[['id', 'target']].to_csv('/home/user/predictions.csv', index=False)
"""

with open('/home/user/pipeline.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
