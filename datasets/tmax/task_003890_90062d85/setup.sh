#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy emcee matplotlib

    mkdir -p /home/user/data
    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(101)
t = np.linspace(0, 10, 50)
# True params: A=5.0, lambda=0.5, B=1.0
y_true = 5.0 * np.exp(-0.5 * t) + 1.0
y_obs = y_true + np.random.normal(0, 0.5, size=len(t))

df = pd.DataFrame({'t': t, 'y': y_obs})
df.to_csv('/home/user/data/decay_data.csv', index=False)
EOF
    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
