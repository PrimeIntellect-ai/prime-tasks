#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs("/home/user/data", exist_ok=True)

# Generate synthetic data that causes overflow
np.random.seed(99)
X = np.random.randn(1000, 5) * 20 + 10  # Large values
true_theta = np.array([0.5, -0.2, 0.1, -0.4, 0.3])
z = np.dot(X, true_theta)
p = 1 / (1 + np.exp(-z))
y = (np.random.rand(1000) < p).astype(float)

np.save("/home/user/data/X.npy", X)
np.save("/home/user/data/y.npy", y)

buggy_code = """import numpy as np
import json

def compute_loss(X, y, theta):
    z = np.dot(X, theta)
    return np.sum(np.log(1 + np.exp(z)) - y * z)

def compute_gradient(X, y, theta):
    z = np.dot(X, theta)
    preds = np.exp(z) / (1 + np.exp(z))
    return np.dot(X.T, (preds - y))

def main():
    X = np.load('/home/user/data/X.npy')
    y = np.load('/home/user/data/y.npy')

    # Initialization
    theta = np.random.randn(X.shape[1])

    lr = 0.001
    max_iters = 10000

    for i in range(max_iters):
        loss = compute_loss(X, y, theta)
        grad = compute_gradient(X, y, theta)
        theta = theta - lr * grad

    # TODO: Save theta.npy and metrics.json

if __name__ == '__main__':
    main()
"""

with open("/home/user/fit_model.py", "w") as f:
    f.write(buggy_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
