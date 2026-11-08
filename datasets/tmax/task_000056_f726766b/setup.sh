#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import scipy.io.wavfile as wav
from scipy.integrate import solve_ivp
import os

def system(t, y):
    x1, x2, v1, v2 = y
    m1, m2 = 1.0, 1.5
    c1, c2 = 0.5, 0.8
    k1, k2, k3 = 50.0, 20.0, 45.0

    a1 = (-c1*v1 - (k1+k2)*x1 + k2*x2) / m1
    a2 = (-c2*v2 - (k2+k3)*x2 + k2*x1) / m2
    return [v1, v2, a1, a2]

t_span = (0, 10)
t_eval = np.linspace(0, 10, 10000, endpoint=False)
y0 = [1.0, 0.0, 0.0, 0.0]

sol = solve_ivp(system, t_span, y0, t_eval=t_eval, method='Radau', rtol=1e-8, atol=1e-8)
x1_signal = sol.y[0].astype(np.float32)

os.makedirs('/app', exist_ok=True)
wav.write('/app/vibration_data.wav', 1000, x1_signal)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
