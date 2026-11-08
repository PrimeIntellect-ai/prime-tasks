#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    # Install system dependencies for Rust and HDF5
    apt-get install -y cargo pkg-config libhdf5-dev

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate initial conditions
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np

np.random.seed(42)
x = np.linspace(0, 1, 50)
data = []
for i in range(10):
    u = np.sin(np.pi * x * (i + 1)) + 0.5 * np.sin(3 * np.pi * x)
    u[0] = 0
    u[-1] = 0
    data.append(u)

data = np.array(data)
np.savetxt('/home/user/initial_conditions.csv', data, delimiter=',')
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Set permissions
    chmod -R 777 /home/user
