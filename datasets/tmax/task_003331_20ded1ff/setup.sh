#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
base_features = np.random.randn(2000, 50)
transformation_matrix = np.random.randn(50, 300)
data = np.dot(base_features, transformation_matrix) + np.random.randn(2000, 300) * 0.1

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_data.csv', index=False, header=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
