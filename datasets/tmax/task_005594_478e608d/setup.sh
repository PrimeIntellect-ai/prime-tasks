#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py

np.random.seed(42)
x0 = np.random.normal(1.0, 0.5, 1000)
v0 = np.random.normal(0.0, 1.0, 1000)
states = np.column_stack((x0, v0))

with h5py.File('/home/user/input_states.h5', 'w') as f:
    f.create_dataset('states', data=states, dtype='float64')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
