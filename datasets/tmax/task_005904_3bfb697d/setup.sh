#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas scipy emcee

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp
import os

gamma_true = 0.15
omega_true = 3.14
sigma = 0.1

def oscillator(t, y, gamma, omega):
    y1, y2 = y
    dy1dt = y2
    dy2dt = -2 * gamma * y2 - omega**2 * y1
    return [dy1dt, dy2dt]

t_eval = np.linspace(0, 10, 100)
sol = solve_ivp(oscillator, [0, 10], [1.0, 0.0], args=(gamma_true, omega_true), t_eval=t_eval, method='RK45')

np.random.seed(99)
y1_obs = sol.y[0] + np.random.normal(0, sigma, size=len(t_eval))

df = pd.DataFrame({'t': t_eval, 'y1_obs': y1_obs})
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/oscillator_data.csv', index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
