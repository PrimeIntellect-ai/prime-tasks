#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import random
import numpy as np
import pandas as pd
from sklearn.datasets import make_classification

os.makedirs('/home/user/experiments', exist_ok=True)

# Generate dataset
X, y = make_classification(n_samples=500, n_features=10, n_informative=5, n_redundant=2, random_state=42)
df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(10)])
df['target'] = y
df.to_csv('/home/user/dataset.csv', index=False)

# Generate experiments
np.random.seed(42)
alphas = np.random.uniform(0.0001, 0.1, 50)
l1_ratios = np.random.uniform(0.0, 1.0, 50)
# Make accuracy somewhat correlated with alpha
accuracies = 0.7 + 2.5 * alphas + np.random.normal(0, 0.05, 50)
accuracies = np.clip(accuracies, 0.0, 1.0)

for i in range(1, 51):
    exp_data = {
        "experiment_id": f"exp_{i:02d}",
        "hyperparameters": {
            "alpha": float(alphas[i-1]),
            "l1_ratio": float(l1_ratios[i-1])
        },
        "metrics": {
            "accuracy": float(accuracies[i-1]),
            "training_time": float(np.random.uniform(0.5, 2.0))
        }
    }
    with open(f'/home/user/experiments/exp_{i:02d}.json', 'w') as f:
        json.dump(exp_data, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
