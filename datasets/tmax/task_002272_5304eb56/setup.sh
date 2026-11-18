#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install --default-timeout=100 pytest numpy pandas scipy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint

def model(y, t):
    A, B, C = y
    k1 = 0.5
    k2 = 0.2
    dA = -k1 * A
    dB = k1 * A - k2 * B
    dC = k2 * B
    return [dA, dB, dC]

t = np.linspace(0, 20, 21)
y0 = [100, 0, 0]
sol = odeint(model, y0, t)

np.random.seed(42)
noise = np.random.normal(0, 2.0, sol.shape)
exp_data = np.clip(sol + noise, 0, None)

df = pd.DataFrame(exp_data, columns=['A', 'B', 'C'])
df['time'] = t
df = df[['time', 'A', 'B', 'C']]
df.to_csv('/home/user/exp_data.csv', index=False)
EOF

python3 /tmp/setup_data.py
rm /tmp/setup_data.py

chmod -R 777 /home/user
