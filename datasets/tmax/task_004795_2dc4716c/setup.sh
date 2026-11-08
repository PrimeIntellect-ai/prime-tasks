#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

# Ground truth parameters
A_true = 4.5
alpha_true = 0.8
f_true = 15.3
phi_true = 0.5
m_true = 1.2
c_true = -0.7

np.random.seed(42)
t = np.linspace(0, 5, 2000)
# True signal
y_true = A_true * np.exp(-alpha_true * t) * np.cos(2 * np.pi * f_true * t + phi_true) + m_true * t + c_true
# Add Gaussian noise
y_noisy = y_true + np.random.normal(0, 0.4, size=t.shape)

df = pd.DataFrame({'t': t, 'y': y_noisy})
df.to_csv('/home/user/ringdown_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
