#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest h5py numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import h5py
import numpy as np

# Generate baseline data
time = np.linspace(0, 10, 100)
T_base = np.sin(time)
T_sim = np.cos(time) * time

with h5py.File('/home/user/baseline.h5', 'w') as f:
    f.create_dataset('time', data=time)
    f.create_dataset('T', data=T_base)

with h5py.File('/home/user/sim_data.h5', 'w') as f:
    f.create_dataset('time', data=time)
    f.create_dataset('T', data=T_sim)

# Compute expected baseline
diff_t = np.diff(time)
diff_T_base = np.diff(T_base)
deriv_base = np.abs(diff_T_base / diff_t)
max_base = np.max(deriv_base)

with open('/home/user/baseline_expected.txt', 'w') as f:
    f.write(f"{max_base:.4f}\n")

# Compute expected sim data (for verification suite)
diff_T_sim = np.diff(T_sim)
deriv_sim = np.abs(diff_T_sim / diff_t)
max_sim = np.max(deriv_sim)

with open('/home/user/.sim_expected_secret.txt', 'w') as f:
    f.write(f"{max_sim:.4f}\n")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
