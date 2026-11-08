#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install --default-timeout=100 pytest numpy pandas scikit-learn

    mkdir -p /app
    espeak -w /app/passphrase.wav "Project Zeus Pipeline."

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl.py
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
import pickle

def run_pipeline():
    np.random.seed(1337)
    X = np.random.exponential(scale=2.0, size=(1000, 5))
    y = X[:, 0] * 3.5 + X[:, 1] * 1.2 - X[:, 2] * 0.5 + np.random.randn(1000) * 0.5

    # DATA LEAK: standardizing before splitting
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

    model = Ridge(alpha=1.0)
    model.fit(X_train, y_train)

    with open('/home/user/model.pkl', 'wb') as f:
        pickle.dump((scaler, model), f)

if __name__ == '__main__':
    run_pipeline()
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
