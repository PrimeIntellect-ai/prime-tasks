#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc jq
    pip3 install pytest numpy scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train_and_plot.py
import numpy as np
from sklearn.linear_model import LogisticRegression
import matplotlib
matplotlib.use('TkAgg') # Hardcoded to force failure in headless unless overridden by env or patched
import matplotlib.pyplot as plt
import sys

if len(sys.argv) < 2:
    print("Please provide a seed")
    sys.exit(1)

np.random.seed(int(sys.argv[1]))
X = np.random.randn(100, 2)
y = (X[:, 0] + X[:, 1] > 0).astype(int)

# Introduce some noise
noise = np.random.choice([0, 1], size=100, p=[0.9, 0.1])
y = np.abs(y - noise)

model = LogisticRegression()
model.fit(X, y)
acc = model.score(X, y)

# Plotting that causes error in headless if TkAgg is used
plt.plot(X[:, 0], X[:, 1], 'ro')
plt.savefig('plot.png')

print(acc)
EOF

    chmod -R 777 /home/user
