#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py emcee

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os
import h5py
import numpy as np
from scipy.integrate import solve_ivp

# Generate ground truth data
np.random.seed(42)
t_eval = np.linspace(0, 10, 100)
k_true, c_true = 5.0, 0.5
sol = solve_ivp(lambda t, y: [y[1], -k_true*y[0] - c_true*y[1]], [0, 10], [1.0, 0.0], t_eval=t_eval)
y_noisy = sol.y[0] + np.random.normal(0, 0.1, size=t_eval.shape)

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('t', data=t_eval)
    f.create_dataset('y', data=y_noisy)

buggy_script = """import h5py
import numpy as np
import emcee
from scipy.integrate import solve_ivp
import json

# Load data
with h5py.File('/home/user/data.h5', 'r') as f:
    t_data = f['t'][:]
    y_data = f['y'][:]

def model(theta, t):
    k, c = theta
    def deriv(t, state):
        y1, y2 = state
        return [y2, -k*y1 - c*y2]
    sol = solve_ivp(deriv, [t[0], t[-1]], [1.0, 0.0], t_eval=t)
    return sol.y[0]

def log_prior(theta):
    # BUG: No constraints on k and c. 
    # MCMC will propose negative values, causing solve_ivp to diverge and return NaNs.
    return 0.0

def log_likelihood(theta, t, y):
    model_y = model(theta, t)
    sigma2 = 0.1**2
    return -0.5 * np.sum((y - model_y)**2 / sigma2 + np.log(2 * np.pi * sigma2))

def log_probability(theta, t, y):
    lp = log_prior(theta)
    if not np.isfinite(lp):
        return -np.inf
    return lp + log_likelihood(theta, t, y)

if __name__ == "__main__":
    nwalkers = 32
    ndim = 2

    # Initialize walkers near expected values
    pos = np.array([4.0, 1.0]) + 1e-4 * np.random.randn(nwalkers, ndim)

    # BUG: Not parallelized
    sampler = emcee.EnsembleSampler(nwalkers, ndim, log_probability, args=(t_data, y_data))

    print("Running MCMC...")
    sampler.run_mcmc(pos, 2000, progress=True)
    print("Done.")
"""

with open('/home/user/fit_model.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
