#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_regression

np.random.seed(42)
X, y = make_regression(n_samples=1000, n_features=19, n_informative=5, noise=0.5, random_state=42)

df = pd.DataFrame(X, columns=[f'feature_{i+1}' for i in range(19)])
df.insert(0, 'id', range(1, 1001))
df['target'] = y

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
