#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 100
featureA = np.random.rand(n) * 10
featureB = np.random.rand(n) * 5
target = 2.0 * featureA + 0.5 * featureB + np.random.randn(n) * 0.1

# Introduce massive outliers
target[12] += 50.0
target[45] -= 40.0
target[88] += 60.0

df = pd.DataFrame({'id': range(1, 101), 'featureA': featureA, 'featureB': featureB, 'target': target})
df.to_csv('/home/user/data/raw_data.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    chmod -R 777 /home/user
