#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/evaluate.py
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import time
import json

# 1. Generate synthetic data
np.random.seed(42)
X = np.random.randn(1000, 20)
X[:500, 0] += 1.5 # Add some signal
y = np.array([1]*500 + [0]*500)

# DATA LEAKAGE: Scaling before splitting
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

# Train model
model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

# Inference benchmarking
start = time.time()
y_pred = model.predict(X_test)
end = time.time()

acc = accuracy_score(y_test, y_pred)
inference_time = end - start

with open('/home/user/metrics.json', 'w') as f:
    json.dump({'accuracy': acc, 'inference_time': inference_time}, f)
EOF

    chmod -R 777 /home/user
