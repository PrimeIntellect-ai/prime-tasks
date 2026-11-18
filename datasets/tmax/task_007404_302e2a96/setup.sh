#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
t = np.linspace(0, 10, 1000, endpoint=False) # 100 Hz sampling
A_true = 2.5
f_true = 3.1415
phi_true = 1.0
sigma_true = 0.5

y = A_true * np.sin(2 * np.pi * f_true * t + phi_true) + np.random.normal(0, sigma_true, size=len(t))

df_obs = pd.DataFrame({'t': t, 'y': y})
df_obs.to_csv('/home/user/observed_signal.csv', index=False)

df_ref = pd.DataFrame({
    'name': ['Alpha_Emission', 'Beta_Decay', 'Gamma_Burst', 'Delta_Wave'],
    'frequency': [1.234, 2.718, 3.142, 4.669]
})
df_ref.to_csv('/home/user/reference.csv', index=False)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
