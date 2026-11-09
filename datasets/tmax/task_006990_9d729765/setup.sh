#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd
from scipy.integrate import quad

os.makedirs('/home/user', exist_ok=True)

np.random.seed(123)
t_vals = np.linspace(0.1, 5.0, 100)
y_vals = [2.0 * quad(lambda x: np.exp(-x**2 / 2), 0, ti)[0] + np.random.normal(0, 0.15) for ti in t_vals]

df = pd.DataFrame({'t': t_vals, 'y': y_vals})
df.to_csv('/home/user/dataset.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
