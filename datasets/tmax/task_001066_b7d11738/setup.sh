#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

np.random.seed(42)
X, y = make_classification(n_samples=1000, n_features=20, n_informative=5, n_redundant=3, n_classes=2, random_state=42)

# Introduce some deliberate highly correlated features
X[:, 5] = X[:, 0] * 0.9 + np.random.normal(0, 0.1, 1000)
X[:, 12] = X[:, 2] * -0.88 + np.random.normal(0, 0.1, 1000)
X[:, 18] = X[:, 1] * 0.95 + np.random.normal(0, 0.05, 1000)

columns = [f"F{i+1}" for i in range(20)]
df = pd.DataFrame(X, columns=columns)
df["is_toxic"] = y
df.to_csv("/home/user/chemical_data.csv", index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
