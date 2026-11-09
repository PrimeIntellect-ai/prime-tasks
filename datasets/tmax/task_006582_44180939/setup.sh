#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
X = np.random.randn(1000, 5)
y = 2.0*X[:,0] - 1.5*X[:,1] + 0.5*X[:,2] + np.random.randn(1000)*0.1
df = pd.DataFrame(X, columns=['x1','x2','x3','x4','x5'])
df['y'] = y
df.to_csv('/home/user/historical_data.csv', index=False)

X_new = np.random.randn(100, 5)
df_new = pd.DataFrame(X_new, columns=['x1','x2','x3','x4','x5'])
df_new.to_csv('/home/user/new_batch.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
