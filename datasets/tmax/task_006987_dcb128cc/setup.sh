#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
import json
from sklearn.datasets import make_classification

# Generate synthetic dataset with strong scaling dependence
X, y = make_classification(n_samples=500, n_features=20, n_informative=15, random_state=100)
# Add an extreme outlier to test set to make the leak obvious
X[400, :] = X[400, :] * 50

df_features = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(20)])
df_features.insert(0, 'id', range(1, 501))
df_features.to_csv('/home/user/data/features.csv', index=False)

labels = [{"id": i+1, "target": int(label)} for i, label in enumerate(y)]
with open('/home/user/data/labels.json', 'w') as f:
    json.dump(labels, f)
EOF

    python3 /home/user/setup_data.py

    cat << 'EOF' > /home/user/train.py
import pandas as pd
import json
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

# 1. Join data
features = pd.read_csv('/home/user/data/features.csv')
with open('/home/user/data/labels.json', 'r') as f:
    labels_data = json.load(f)
labels = pd.DataFrame(labels_data)
df = pd.merge(features, labels, on='id')

X = df.drop(['id', 'target'], axis=1)
y = df['target']

# 2. DATA LEAK: Scale before splitting
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# 3. Split
X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.3, random_state=42)

# 4. Train
model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

# 5. Evaluate
y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)
print(f"Leaky Accuracy: {accuracy:.4f}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
