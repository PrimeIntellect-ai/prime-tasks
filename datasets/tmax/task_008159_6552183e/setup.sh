#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd
from scipy.integrate import odeint

np.random.seed(42)
def model_eq(y, t, k, c):
    return -k * y - c * y**2

t = np.linspace(0, 5, 25)
y_true = odeint(model_eq, 10.0, t, args=(0.5, 0.2)).flatten()
y_obs = y_true + np.random.normal(0, 0.5, size=len(t))

df = pd.DataFrame({'time': t, 'y': y_obs})
df.to_csv('/home/user/decay_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
