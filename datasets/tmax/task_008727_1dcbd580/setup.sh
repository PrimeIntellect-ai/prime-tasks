#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py emcee

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import h5py
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/results', exist_ok=True)

np.random.seed(123)
time = np.linspace(0, 10, 1000)
flux = np.ones((100, 1000)) + np.random.normal(0, 0.005, (100, 1000))

# Inject a prominent transit signal in index 41
A_true = 0.05
t0_true = 4.5
sigma_true = 0.3

flux[41] = 1.0 - A_true * np.exp(-0.5 * ((time - t0_true) / sigma_true)**2) + np.random.normal(0, 0.005, 1000)

with h5py.File('/home/user/data/lightcurves.h5', 'w') as f:
    f.create_dataset('time', data=time)
    f.create_dataset('flux', data=flux)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
