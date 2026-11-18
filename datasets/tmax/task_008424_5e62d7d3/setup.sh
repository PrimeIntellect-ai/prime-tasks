#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
from sklearn.datasets import make_classification
import pandas as pd

X, y = make_classification(n_samples=1000, n_features=20, random_state=1)
df = pd.DataFrame(X)
df['target'] = y
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/train.py
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import json

# Load data
df = pd.read_csv('/home/user/data.csv')
X = df.drop('target', axis=1)
y = df['target']

# BUG: Data Leakage (scaling before split)
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

preds = model.predict(X_test)
acc = accuracy_score(y_test, preds)

with open('/home/user/metrics.json', 'w') as f:
    json.dump({'accuracy': acc}, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
