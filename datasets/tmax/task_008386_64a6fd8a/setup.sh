#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

def sir(t, y, beta, gamma, N):
    S, I, R = y
    dS = -beta * S * I / N
    dI = beta * S * I / N - gamma * I
    dR = gamma * I
    return [dS, dI, dR]

N = 1000
y0 = [995, 5, 0]
t_span = (0, 50)
t_eval = np.arange(51)

sol = solve_ivp(sir, t_span, y0, args=(0.35, 0.15, N), t_eval=t_eval)
np.random.seed(99)
noise = np.random.normal(0, 5, size=len(t_eval))
I_obs = np.clip(sol.y[1] + noise, 0, None)

df = pd.DataFrame({'t': t_eval, 'I_obs': I_obs})
df.to_csv('/home/user/observed_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
