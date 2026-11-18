#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_env.py
import os
import numpy as np
from scipy.integrate import odeint

def sir_model(y, t, beta, gamma):
    S, I, R = y
    dSdt = -beta * S * I
    dIdt = beta * S * I - gamma * I
    dRdt = gamma * I
    return [dSdt, dIdt, dRdt]

t = np.linspace(0, 20, 21)
y0 = [0.99, 0.01, 0.0]
# True params: beta=1.2, gamma=0.3
res = odeint(sir_model, y0, t, args=(1.2, 0.3))
I_true = res[:, 1]

np.random.seed(999)
I_obs = I_true + np.random.normal(0, 0.02, size=len(I_true))
I_obs = np.clip(I_obs, 0, 1)

with open('/home/user/observations.csv', 'w') as f:
    f.write('day,infected\n')
    for day, inf in zip(t, I_obs):
        f.write(f'{int(day)},{inf:.6f}\n')
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    chmod -R 777 /home/user
