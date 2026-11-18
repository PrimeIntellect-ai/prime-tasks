#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/evaluate_model.py
import numpy as np
from sklearn.datasets import make_classification
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import cross_val_score
import json
import os

# Generate dataset
X, y = make_classification(n_samples=500, n_features=20, n_informative=15, random_state=42)

# BUG: Data leakage
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

model = LogisticRegression(random_state=42)
scores = cross_val_score(model, X_scaled, y, cv=5)

print(f"Mean CV Accuracy: {np.mean(scores)}")
EOF

    chmod -R 777 /home/user
