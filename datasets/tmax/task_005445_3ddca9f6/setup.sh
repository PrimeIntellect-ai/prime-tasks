#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
x = np.linspace(0, 10, 1000)
y_clean = np.sin(x)
ref_dy = np.gradient(y_clean)
y_sensor = y_clean + 1e-3 * np.sin(100 * x)

np.savetxt('/home/user/sensor_data.csv', y_sensor, fmt='%.8f')
np.savetxt('/home/user/ref_derivative.csv', ref_dy, fmt='%.8f')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
