#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(123)
X = np.random.randn(1000, 50)
X[:, 10:20] = X[:, 0:10] * 0.5 + np.random.randn(1000, 10) * 0.1
df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(50)])
df.to_csv('/home/user/telemetry.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
