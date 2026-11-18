#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user/build_system
    cd /home/user/build_system

    cat << 'EOF' > dataset.csv
A,B,C,D,Y
0.5,1.2,-0.5,1000,5.0
-1.0,0.0,2.0,-2000,-10.0
1.5,-1.5,0.0,1500,7.5
0.0,0.5,-1.0,500,2.5
-0.5,-0.5,1.5,-500,-2.5
2.0,1.0,1.0,2000,10.0
-2.0,-1.0,-1.0,-2500,-12.5
1.0,2.0,-2.0,1200,6.0
-1.5,-2.0,2.5,-1800,-9.0
0.2,0.8,-0.2,800,4.0
EOF

    cat << 'EOF' > train.py
import numpy as np
import pandas as pd
import os

def load_data():
    df = pd.read_csv('dataset.csv')
    X = df[['A', 'B', 'C', 'D']].values.astype(float)
    y = df['Y'].values.astype(float)
    return X, y

def preprocess(X):
    # BUG: The slicing only scales the first 3 columns (indices 0, 1, 2)
    # Column D (index 3) is left unscaled, causing gradient explosion.
    X[:, :3] = (X[:, :3] - np.mean(X[:, :3], axis=0)) / np.std(X[:, :3], axis=0)
    return X

def train(X, y):
    np.random.seed(42)
    weights = np.random.randn(X.shape[1])
    lr = 0.01

    for epoch in range(100):
        predictions = X.dot(weights)
        errors = predictions - y
        gradient = X.T.dot(errors) / len(y)
        weights -= lr * gradient
        loss = np.mean(errors**2)

        if np.isnan(loss) or np.isinf(loss):
            raise ValueError("Convergence failure: Loss is NaN/Inf")

    if loss > 15.0:
        raise ValueError(f"Build failed: Final loss {loss:.4f} is too high. Expected < 15.0")

    np.save('weights.npy', weights)
    print("Build passed!")

if __name__ == "__main__":
    X, y = load_data()
    X = preprocess(X)
    train(X, y)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
