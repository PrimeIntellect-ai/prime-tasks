#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

n_samples = 500
n_features = 50

clusters = np.random.randn(n_samples, 3)
clusters[:150] += np.array([5, 5, 5])
clusters[150:350] += np.array([-5, -5, 5])
clusters[350:] += np.array([5, -5, -5])

projection_matrix = np.random.randn(3, n_features)
X = np.dot(clusters, projection_matrix) + np.random.randn(n_samples, n_features) * 2

df = pd.DataFrame(X, columns=[f'f{i}' for i in range(n_features)])
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/gen_data.py

    chmod -R 777 /home/user
