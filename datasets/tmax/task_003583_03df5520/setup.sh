#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
X = np.random.randn(100, 3)
# Create a relationship where f1 and f2 are predictive
y = 2.0 * X[:, 0] + 0.5 * X[:, 1] + np.random.randn(100) * 0.5

df_f = pd.DataFrame(X, columns=['f1', 'f2', 'f3'])
df_f['sample_id'] = range(100)
# Reorder columns to match standard 
df_f = df_f[['sample_id', 'f1', 'f2', 'f3']]

df_t = pd.DataFrame({'sample_id': range(100), 'target': y})

df_f.to_csv('/home/user/features.csv', index=False)
df_t.to_csv('/home/user/targets.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
