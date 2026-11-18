#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
from sklearn.datasets import make_classification
import os

os.makedirs("/home/user", exist_ok=True)
X, y = make_classification(n_samples=200, n_features=30, n_informative=10, n_redundant=10, random_state=42)
df = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(30)])
df["target"] = y
df.to_csv("/home/user/data.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
