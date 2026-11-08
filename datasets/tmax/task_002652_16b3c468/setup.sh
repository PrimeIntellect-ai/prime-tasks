#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint

def kinetics(y, t, k1, k2, k3):
    A, B, C = y
    dA = -k1 * A
    dB = k1 * A - k2 * B**2
    dC = k2 * B**2 - k3 * C
    return [dA, dB, dC]

t = np.linspace(0, 20, 21)
y0 = [10.0, 0.0, 0.0]
k1_true, k2_true, k3_true = 0.5, 0.2, 0.1

sol = odeint(kinetics, y0, t, args=(k1_true, k2_true, k3_true))

df = pd.DataFrame({'t': t, 'A': sol[:,0], 'B': sol[:,1], 'C': sol[:,2]})
df.to_csv('/home/user/kinetics_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
