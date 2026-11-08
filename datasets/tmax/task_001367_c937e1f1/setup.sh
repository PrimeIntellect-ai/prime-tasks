#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py
from scipy.integrate import solve_ivp

def vdp(t, y, mu):
    return [y[1], mu * (1 - y[0]**2) * y[1] - y[0]]

mu_true = 500.0
t_span = (0, 2000)
t_eval = np.linspace(0, 2000, 200)

sol = solve_ivp(vdp, t_span, [2.0, 0.0], method='Radau', t_eval=t_eval, args=(mu_true,))

with h5py.File('/home/user/vdp_target.h5', 'w') as f:
    f.create_dataset('t', data=sol.t)
    f.create_dataset('y', data=sol.y[0])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
