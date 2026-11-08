#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv python3-h5py
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the unstable Python script
    cat << 'EOF' > simulate_selection.py
import numpy as np
import h5py

def get_params():
    with h5py.File('params.h5', 'r') as f:
        y0 = f['y0'][()]
        r = f['r'][()]
        m = f['m'][()]
    return y0, r, m

def simulate():
    y0, r, m = get_params()

    # Unstable explicit Euler integration
    dt = 0.1
    t_end = 10.0
    times = np.arange(0, t_end, dt)
    y = np.zeros(len(times))
    y[0] = y0

    for i in range(1, len(times)):
        dy = r * y[i-1] * (1 - y[i-1]) - m * y[i-1]
        y[i] = y[i-1] + dy * dt

    print(f"Final frequency: {y[-1]}")

if __name__ == '__main__':
    simulate()
EOF

    # Create the HDF5 params file
    python3 -c "
import h5py
with h5py.File('params.h5', 'w') as f:
    f.create_dataset('y0', data=0.01)
    f.create_dataset('r', data=150.0) # Highly stiff
    f.create_dataset('m', data=30.0)
"

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
