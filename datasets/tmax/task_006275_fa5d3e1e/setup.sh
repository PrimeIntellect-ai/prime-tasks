#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Generate telemetry.csv
np.random.seed(42)
n_samples = 1000
f1 = np.random.normal(0, 1, n_samples)
f2 = np.random.normal(5, 2, n_samples)
f3 = f1 * 2 + np.random.normal(0, 0.5, n_samples)
f4 = np.random.uniform(-1, 1, n_samples)
f5 = np.random.normal(0, 5, n_samples)

labels = (f1 + f2 * 0.5 > 2.5).astype(int)

df = pd.DataFrame({
    'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'f5': f5, 'label': labels
})
df.to_csv('/home/user/telemetry.csv', index=False)

# Create buggy pipeline.py
buggy_code = """import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
import json

df = pd.read_csv('/home/user/telemetry.csv')
X = df.drop('label', axis=1)
y = df['label']

# Bug: Data Leakage
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

pca = PCA(n_components=2)
X_pca = pca.fit_transform(X_scaled)

X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42)

clf = LogisticRegression(random_state=42)
clf.fit(X_train, y_train)
acc = clf.score(X_test, y_test)

results = {
    'accuracy': acc
}

with open('/home/user/results.json', 'w') as f:
    json.dump(results, f)
"""
with open('/home/user/pipeline.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
