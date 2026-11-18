#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate the initial data
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
t = np.linspace(0, 10, 1024)
# Hidden artifact signal at 15Hz
signal = np.sin(2 * np.pi * 15 * t)
U_vec = np.random.randn(50, 1)
# Create noisy data matrix
X = U_vec @ signal.reshape(1, 1024) + np.random.randn(50, 1024) * 0.5
np.savetxt('/home/user/sensor_data.csv', X, delimiter=',')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
