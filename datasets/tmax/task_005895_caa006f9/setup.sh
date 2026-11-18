#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

# Create reference data
np.random.seed(100)
t = np.linspace(0, 50, 20)
T_exact = 20.0 + 80.0 * np.exp(-0.15 * t)
T_noisy = T_exact + np.random.normal(0, 2.0, size=len(t))

np.savetxt('/home/user/reference_data.csv', np.column_stack((t, T_noisy)), delimiter=',')

# Create mcmc_ode.py
mcmc_code = """import numpy as np
from scipy.integrate import odeint

def cooling_model(T, t, k):
    return -k * (T - 20.0)

def run_mcmc(seed):
    np.random.seed(seed)
    data = np.loadtxt('/home/user/reference_data.csv', delimiter=',')
    t_data = data[:, 0]
    T_data = data[:, 1]

    k_current = 0.1
    n_steps = 1500
    samples = []

    for _ in range(n_steps):
        k_proposal = k_current + np.random.normal(0, 0.02)
        if k_proposal <= 0:
            samples.append(k_current)
            continue

        T_proposal = odeint(cooling_model, 100.0, t_data, args=(k_proposal,)).flatten()
        T_current = odeint(cooling_model, 100.0, t_data, args=(k_current,)).flatten()

        ll_proposal = -0.5 * np.sum((T_data - T_proposal)**2) / (2.0**2)
        ll_current = -0.5 * np.sum((T_data - T_current)**2) / (2.0**2)

        if np.log(np.random.rand()) < (ll_proposal - ll_current):
            k_current = k_proposal

        samples.append(k_current)

    return np.mean(samples[500:])
"""

with open('/home/user/mcmc_ode.py', 'w') as f:
    f.write(mcmc_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
