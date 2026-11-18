#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_dataset.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_regression

# Generate a synthetic dataset
X, y = make_regression(
    n_samples=600, 
    n_features=50, 
    n_informative=6, 
    noise=15.0, 
    random_state=42
)
df = pd.DataFrame(X, columns=[f"f{i}" for i in range(1, 51)])
df["target"] = y
df.to_csv("/home/user/dataset.csv", index=False)
EOF

    python3 /tmp/generate_dataset.py
    rm /tmp/generate_dataset.py

    chmod -R 777 /home/user
