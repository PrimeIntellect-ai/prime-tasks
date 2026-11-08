#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn pandas

    mkdir -p /home/user
    cat << 'EOF' > /tmp/generate_data.py
import os
from sklearn.datasets import make_classification
import pandas as pd

os.makedirs('/home/user', exist_ok=True)
X, y = make_classification(n_samples=1000, n_features=10, n_informative=8, n_redundant=2, random_state=42)
df = pd.DataFrame(X)
df['target'] = y
df.to_csv('/home/user/data.csv', index=False, header=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
