#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd
from sklearn.datasets import make_classification

# Generate dataset
np.random.seed(42)
X, y = make_classification(n_samples=500, n_features=10, n_informative=5, random_state=42)

# Inject missing values
mask = np.random.rand(*X.shape) < 0.1
X[mask] = np.nan

# Inject outliers
outlier_mask = np.random.rand(*X.shape) < 0.05
X[outlier_mask] = X[outlier_mask] * 10

df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(10)])
df['target'] = y
df.to_csv('/home/user/data.csv', index=False)

# Create leaky script
leaky_code = """import pandas as pd
import numpy as np
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score

df = pd.read_csv('data.csv')
X = df.drop('target', axis=1)
y = df['target']

# DATA LEAKAGE: Imputing and scaling before CV
imputer = SimpleImputer(strategy='mean')
X_imputed = imputer.fit_transform(X)

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_imputed)

clf = RandomForestClassifier(n_estimators=100, random_state=42)
scores = cross_val_score(clf, X_scaled, y, cv=5)
print(f"Leaky CV Accuracy: {np.mean(scores):.4f}")
"""
with open('/home/user/leaky_train.py', 'w') as f:
    f.write(leaky_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
