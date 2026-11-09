#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy python3-h5py
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

np.random.seed(42)
time = np.arange(10000)
raw_signal = 1.5 * np.sin(0.01 * time) + np.random.normal(0, 0.2, 10000)

step_indices = [1500, 3200, 6800, 8500]
for idx in step_indices:
    raw_signal[idx:] += 2.0

x_gauss = np.arange(500)
true_A = 5.234
true_mu = 230.15
true_sigma = 35.8
gauss = true_A * np.exp(-((x_gauss - true_mu)**2) / (2 * true_sigma**2))
raw_signal[2000:2500] += gauss

with h5py.File('/home/user/nanopore_sim.h5', 'w') as f:
    f.create_dataset('signal', data=raw_signal)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
