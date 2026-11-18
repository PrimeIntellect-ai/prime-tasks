#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

np.random.seed(42)

# True parameters
c_true = 0.8
k_true = 25.0
F_true = 3.5
omega_true = 15.0 # rad/s
t_span = (0, 10)
t_eval = np.sort(np.random.uniform(0, 10, 800)) # Irregular sampling
t_eval[0] = 0.0

def ode_system(t, y):
    x, v = y
    dxdt = v
    dvdt = F_true * np.sin(omega_true * t) - c_true * v - k_true * x
    return [dxdt, dvdt]

sol = solve_ivp(ode_system, t_span, [0.0, 0.0], t_eval=t_eval, method='RK45', rtol=1e-8, atol=1e-8)

# Add noise
noise = np.random.normal(0, 0.05, len(t_eval))
displacement = sol.y[0] + noise

df = pd.DataFrame({'time': t_eval, 'displacement': displacement})
df.to_csv('/home/user/data/sensor_readings.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
