#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py
from scipy.integrate import solve_ivp
import os

os.makedirs('/home/user', exist_ok=True)

# Generate observational data
def vdp(t, y, mu):
    return [y[1], mu * (1 - y[0]**2) * y[1] - y[0]]

t_span = (0, 3000)
t_eval = np.linspace(0, 3000, 500)
y0 = [2.0, 0.0]
mu_true = 1000

sol = solve_ivp(vdp, t_span, y0, args=(mu_true,), method='BDF', t_eval=t_eval, rtol=1e-6, atol=1e-9)

with h5py.File('/home/user/observational_data.h5', 'w') as f:
    f.create_dataset('time', data=sol.t)
    f.create_dataset('y1', data=sol.y[0])
    f.create_dataset('y2', data=sol.y[1])

# Create the broken simulate.py
simulate_code = """import numpy as np
from scipy.integrate import solve_ivp

def vanderpol(t, y, mu):
    return [y[1], mu * (1 - y[0]**2) * y[1] - y[0]]

def run_simulation(mu, t_eval):
    y0 = [2.0, 0.0]
    # BUG: RK45 will hang/fail for stiff equations like Van der Pol with high mu
    sol = solve_ivp(vanderpol, (t_eval[0], t_eval[-1]), y0, args=(mu,), method='RK45', t_eval=t_eval)
    return sol.y[0]
"""

with open('/home/user/simulate.py', 'w') as f:
    f.write(simulate_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
