#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_env.py
import h5py
import numpy as np
import os

np.random.seed(123)
file_path = "/home/user/sim_data.h5"

with h5py.File(file_path, "w") as f:
    for i in range(100):
        grp = f.create_group(f"sim_{i}")
        t = np.linspace(0, 5, 100)

        # 60 good simulations, 40 bad simulations
        is_good = np.random.rand() < 0.6

        if is_good:
            # Good: analytical + small noise
            y = np.exp(-0.5 * t) + np.random.normal(0, 0.01, size=t.shape)
        else:
            # Bad: diverging or oscillating wildly
            y = np.exp(0.1 * t) * np.sin(5 * t) + np.random.normal(0, 0.5, size=t.shape)

        grp.create_dataset("t", data=t)
        grp.create_dataset("y", data=y)

os.chmod(file_path, 0o644)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
