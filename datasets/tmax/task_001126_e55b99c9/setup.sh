#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/pipeline
    cat << 'EOF' > /home/user/pipeline/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(10)
N = 1000
f1 = np.random.randn(N)
f2 = np.random.randn(N) * 2
f3 = np.random.randn(N) * 0.5
f4 = np.random.randn(N) + 1.5

# Introduce multicollinearity and target
target = 3.5 * f1 - 1.2 * f2 + 0.8 * f3 + np.random.randn(N) * 0.5

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'target': target})

# Introduce some NaNs
df.loc[10:15, 'f2'] = np.nan
df.loc[100:105, 'f1'] = np.nan

df.to_csv('/home/user/pipeline/data.csv', index=False)
EOF
    python3 /home/user/pipeline/generate_data.py
    rm /home/user/pipeline/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
