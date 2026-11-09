#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint

def model(z, t, a, b, c, d):
    x, y = z
    dxdt = -a * x + b * y
    dydt = c * x - d * (y**2)
    return [dxdt, dydt]

# Ground truth parameters
a, b, c, d = 0.5, 0.2, 0.8, 0.3
z0 = [1.0, 2.0]
t = np.linspace(0, 10, 21)

# Generate data
z = odeint(model, z0, t, args=(a, b, c, d))

# Add a tiny bit of noise (or no noise to ensure exact parameter recovery)
np.random.seed(42)
noise_x = np.random.normal(0, 0.01, size=len(t))
noise_y = np.random.normal(0, 0.01, size=len(t))

df = pd.DataFrame({
    't': t,
    'x': z[:, 0] + noise_x,
    'y': z[:, 1] + noise_y
})
df.to_csv('/home/user/experiment_data.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
