#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas scikit-learn

mkdir -p /home/user

cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
# Generate features
X = np.random.randn(200, 10)
# Introduce correlation
A = np.random.randn(10, 10)
X = X @ A

# Generate target
y = X[:, 0] * 2.0 + X[:, 1] * -1.5 + X[:, 2] * 0.5 + np.random.randn(200) * 0.1

df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(10)])
df['target'] = y
df.to_csv("/home/user/dataset.csv", index=False)
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
