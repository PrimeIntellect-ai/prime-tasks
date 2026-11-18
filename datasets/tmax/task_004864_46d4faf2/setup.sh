#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn pyarrow

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
n = 500
ids = np.arange(1, n+1)
A = np.random.uniform(1, 10, n)
B = np.random.uniform(0, 5, n)

# Introduce some exact zeros in B to cause division by zero
zero_indices = np.random.choice(n, 20, replace=False)
B[zero_indices] = 0.0

# Calculate target
Ratio = np.where(B == 0, np.nan, A / B)
Target = 2.0 * A + 3.0 * B + 0.5 * np.nan_to_num(Ratio, nan=0.0) + np.random.normal(0, 1, n)

df = pd.DataFrame({'ID': ids, 'Feature_A': A, 'Feature_B': B, 'Target': Target})
# introduce some NaNs to test dropping
df.loc[10:15, 'Target'] = np.nan

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
