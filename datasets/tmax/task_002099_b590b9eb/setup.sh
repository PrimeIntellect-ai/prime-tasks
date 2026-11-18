#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
X = np.random.randn(1000, 20)
# True relation
y = X[:, 0] * 2.5 + X[:, 3] * -1.2 + np.random.randn(1000) * 0.5

df = pd.DataFrame(X, columns=[f'f_{i}' for i in range(20)])
df['y'] = y

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
