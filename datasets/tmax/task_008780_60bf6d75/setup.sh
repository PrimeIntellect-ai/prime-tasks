#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_ref.py
import numpy as np
import h5py
from scipy.integrate import odeint

def oscillator(state, t, c, k):
    y, v = state
    dydt = v
    dvdt = -c*v - k*y
    return [dydt, dvdt]

t = np.linspace(0, 10, 100)
state0 = [1.0, 0.0]
c_true = 0.5
k = 10.0

solution = odeint(oscillator, state0, t, args=(c_true, k))
y_ref = solution[:, 0]

with h5py.File('/home/user/reference.h5', 'w') as f:
    f.create_dataset('y_ref', data=y_ref)
EOF

    python3 /tmp/generate_ref.py
    rm /tmp/generate_ref.py

    chmod -R 777 /home/user
