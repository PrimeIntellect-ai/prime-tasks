#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd
from sklearn.datasets import make_regression
import json

# 1. Generate Data
X, y = make_regression(n_samples=500, n_features=5, noise=15.0, random_state=100)
df = pd.DataFrame(X, columns=[f'f{i+1}' for i in range(5)])
df['target'] = y
df['metadata'] = 'ignore_me_v1'
df.to_csv('/home/user/data.csv', index=False)

# 2. Generate Schema
schema = {
    "columns": {
        "f1": "float",
        "f2": "float",
        "f3": "float",
        "f4": "float",
        "f5": "float",
        "target": "float"
    }
}
with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f)

# 3. Generate Leaky Script
train_code = """import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

df = pd.read_csv('/home/user/data.csv')
df = df.drop(columns=['metadata']) # manual drop

X = df.drop(columns=['target'])
y = df['target']

# DATA LEAK
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = Ridge(alpha=1.0)
model.fit(X_train, y_train)

preds = model.predict(X_test)
print(f"MSE: {mean_squared_error(y_test, preds)}")
"""
with open('/home/user/train.py', 'w') as f:
    f.write(train_code)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
