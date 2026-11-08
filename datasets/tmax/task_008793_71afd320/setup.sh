#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)
X = np.random.randn(1000, 4)
y = 2.5 * X[:, 0] - 1.2 * X[:, 1] + np.random.randn(1000) * 0.5
df = pd.DataFrame(X, columns=['x1', 'x2', 'x3', 'x4'])
df['y'] = y

os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
