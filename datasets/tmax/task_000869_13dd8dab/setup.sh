#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
X = np.random.randn(100, 2)
# Create a target with some noise
y = X[:, 0] * 2 + X[:, 1] * 0.5 + np.random.randn(100) * 1.5

df = pd.DataFrame(X, columns=['f1', 'f2'])
df['target'] = y

# Inject an outlier
df.loc[10, 'target'] = 5000.0

# Inject missing values
df.loc[20:25, 'f1'] = np.nan

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
