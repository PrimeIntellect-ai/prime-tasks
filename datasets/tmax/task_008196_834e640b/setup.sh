#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp
import os

def oscillator(t, y):
    x, v = y
    return [v, -0.2*v - 5.0*x]

t_span = (0, 10)
t_eval = np.linspace(0, 10, 101)
sol = solve_ivp(oscillator, t_span, [1.0, 0.0], t_eval=t_eval)

np.random.seed(42)
exact_x = sol.y[0]

# Run 0: Valid (small noise, MSE approx 0.001)
noise0 = np.random.normal(0, 0.03, len(t_eval))
pd.DataFrame({'time': t_eval, 'x_measured': exact_x + noise0}).to_csv('/home/user/sensor_data/run_0.csv', index=False)

# Run 1: Invalid (high noise, MSE approx 0.1)
noise1 = np.random.normal(0, 0.3, len(t_eval))
pd.DataFrame({'time': t_eval, 'x_measured': exact_x + noise1}).to_csv('/home/user/sensor_data/run_1.csv', index=False)

# Run 2: Invalid (wrong frequency)
sol_wrong = solve_ivp(lambda t, y: [y[1], -0.2*y[1] - 8.0*y[0]], t_span, [1.0, 0.0], t_eval=t_eval)
pd.DataFrame({'time': t_eval, 'x_measured': sol_wrong.y[0]}).to_csv('/home/user/sensor_data/run_2.csv', index=False)

# Run 3: Valid (very small noise, MSE approx 0.0001)
noise3 = np.random.normal(0, 0.01, len(t_eval))
pd.DataFrame({'time': t_eval, 'x_measured': exact_x + noise3}).to_csv('/home/user/sensor_data/run_3.csv', index=False)

# Run 4: Invalid (completely broken sensor, flatline)
pd.DataFrame({'time': t_eval, 'x_measured': np.zeros_like(t_eval)}).to_csv('/home/user/sensor_data/run_4.csv', index=False)
EOF

    python3 /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
