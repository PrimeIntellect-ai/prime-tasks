#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint

def model(y, t, k1, k2):
    plasma, tissue = y
    dp_dt = -k1 * plasma + k2 * tissue
    dt_dt = k1 * plasma - k2 * tissue
    return [dp_dt, dt_dt]

k1_true = 0.5
k2_true = 0.2
y0 = [1.0, 0.0]
t_eval = np.linspace(0, 10, 50)

sol = odeint(model, y0, t_eval, args=(k1_true, k2_true))

np.random.seed(42)
noise_p = np.random.normal(0, 0.01, size=sol[:,0].shape)
noise_t = np.random.normal(0, 0.01, size=sol[:,1].shape)

df = pd.DataFrame({
    'time': t_eval,
    'plasma_conc': np.clip(sol[:, 0] + noise_p, 0, None),
    'tissue_conc': np.clip(sol[:, 1] + noise_t, 0, None)
})

df.to_csv('/home/user/drug_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
