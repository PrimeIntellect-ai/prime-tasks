#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)

np.random.seed(100)
X = np.random.randn(1000, 5) * 10 + 5
mask = np.random.rand(*X.shape) < 0.1
X[mask] = np.nan

y = (X[:, 0] * 0.5 + X[:, 1] * -0.3 + np.random.randn(1000) > 2).astype(int)

df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(5)])
df['target'] = y

df.to_csv('/home/user/data/raw.csv', index=False)

flawed_script = """import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import json

def main():
    df = pd.read_csv('/home/user/data/raw.csv')
    X = df.drop('target', axis=1)
    y = df['target']

    # --- DATA LEAKAGE: Fitting on entire dataset ---
    imputer = SimpleImputer(strategy='mean')
    X_imputed = imputer.fit_transform(X)

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_imputed)
    # -----------------------------------------------

    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

    model = LogisticRegression(random_state=42)
    model.fit(X_train, y_train)
    preds = model.predict(X_test)

    acc = accuracy_score(y_test, preds)

    # Calculate the mean of the first feature of the test set
    f0_mean = float(np.mean(X_test[:, 0]))

    metrics = {
        'accuracy': float(acc),
        'test_feature_0_mean': f0_mean
    }

    with open('/home/user/metrics.json', 'w') as f:
        json.dump(metrics, f, indent=4)

if __name__ == "__main__":
    main()
"""

with open('/home/user/train_pipeline.py', 'w') as f:
    f.write(flawed_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
