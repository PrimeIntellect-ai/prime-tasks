#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
N, p = 100, 10
X1 = np.random.randn(N, 1)
X = np.hstack([X1 + 0.01 * np.random.randn(N, 1) for _ in range(p)])
X += 0.05 * np.random.randn(N, p)
true_coef = np.random.randn(p)
y = X @ true_coef + np.random.randn(N)

pd.DataFrame(X).to_csv('/home/user/X.csv', index=False)
pd.DataFrame(y).to_csv('/home/user/y.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
