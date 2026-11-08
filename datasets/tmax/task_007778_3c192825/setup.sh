#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
from sklearn.datasets import make_classification
import os

os.makedirs('/home/user', exist_ok=True)

X, y = make_classification(
    n_samples=2000, 
    n_features=20, 
    n_informative=10, 
    n_redundant=5, 
    random_state=123
)

df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(20)])
df['target'] = y

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
