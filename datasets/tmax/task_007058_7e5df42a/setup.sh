#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
n = 500
A = np.random.uniform(0, 10, n)
B = np.random.uniform(0, 10, n)
C = 2.5 * A - 1.2 * B + np.random.normal(0, 1.0, n)

df = pd.DataFrame({'id': range(n), 'sensor_A': A, 'sensor_B': B, 'sensor_C': C})

# drop 20%
drop_idx = np.random.choice(n, int(0.2*n), replace=False)
df.loc[drop_idx, 'sensor_C'] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
