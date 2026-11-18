#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np

np.random.seed(123)
x = np.arange(50)
y = np.arange(50)
X, Y = np.meshgrid(x, y, indexing='ij')

A_true = 5.5
sigma_s_true = 3.2
sigma_noise = 0.5

C = A_true * np.exp(-((X - 25)**2 + (Y - 25)**2) / (2 * sigma_s_true**2))
D = C + np.random.normal(0, sigma_noise, size=C.shape)

np.save('/home/user/assay_data.npy', D)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
