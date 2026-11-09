#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n = 100
f1 = np.random.randn(n)
f2 = f1 + np.random.randn(n) * 0.1  # highly correlated with f1
f3 = np.random.randn(n)
f4 = np.random.randn(n)
f5 = -f3 + np.random.randn(n) * 0.1 # highly negatively correlated with f3

# Target y
y = 2.0 * f1 + 1.5 * f3 - 0.5 * f4 + np.random.randn(n) * 0.5

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'f5': f5, 'y': y})
df.to_csv('sensor_data.csv', index=False)
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
