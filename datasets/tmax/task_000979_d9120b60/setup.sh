#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint

def sir_model(y, t, beta, gamma):
    S, I, R = y
    N = 1000
    dS = -beta * S * I / N
    dI = beta * S * I / N - gamma * I
    dR = gamma * I
    return [dS, dI, dR]

t = np.linspace(0, 50, 51)
y0 = [990, 10, 0]
beta_true, gamma_true = 0.4, 0.1

sol = odeint(sir_model, y0, t, args=(beta_true, gamma_true))
S, I, R = sol.T

np.random.seed(100)
I_noisy = I + np.random.normal(0, 15, len(I))
I_noisy = np.clip(I_noisy, 0, None)

df = pd.DataFrame({'t': t, 'S': S, 'I': I_noisy, 'R': R})
df.to_csv('/home/user/data/experimental.csv', index=False)
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
