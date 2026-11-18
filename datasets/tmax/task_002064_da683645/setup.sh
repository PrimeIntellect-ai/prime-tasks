#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py nbformat jupyter nbconvert

    mkdir -p /home/user

    python3 -c "
import os
import h5py
import numpy as np
import nbformat
from nbformat.v4 import new_notebook, new_code_cell

os.makedirs('/home/user', exist_ok=True)

# 1. Generate observations.h5
t = np.linspace(0, 5, 50)
y_true = (1 - 1.0/2.0) * np.exp(-2.0 * t) + 1.0/2.0
np.random.seed(42)
y_obs = y_true + np.random.normal(0, 0.05, size=len(t))

with h5py.File('/home/user/observations.h5', 'w') as f:
    f.create_dataset('t', data=t)
    f.create_dataset('y', data=y_obs)

# 2. Generate mcmc_fit.ipynb
nb_code = \"\"\"
import h5py
import numpy as np
import math

# Load observations
with h5py.File('/home/user/observations.h5', 'r') as f:
    t_obs = f['t'][:]
    y_obs = f['y'][:]

def integrate_ode(alpha, beta, t_eval):
    dt = 0.5 # BUG: Step size too large, causes divergence
    y = np.zeros(len(t_eval))
    y[0] = 1.0

    y_curr = 1.0
    t_curr = t_eval[0]
    idx = 1

    # Simple Euler integration
    while idx < len(t_eval):
        while t_curr < t_eval[idx]:
            step = min(dt, t_eval[idx] - t_curr)
            y_curr = y_curr + step * (-alpha * y_curr**3 + beta) # non-linear to force blowup with large dt
            t_curr += step
        y[idx] = y_curr
        idx += 1
    return y

def log_likelihood(theta):
    alpha, beta = theta
    if alpha < 0 or beta < 0:
        return -np.inf

    try:
        y_pred = integrate_ode(alpha, beta, t_obs)
        if np.any(np.isnan(y_pred)) or np.any(np.isinf(y_pred)):
            return -np.inf

        sigma = 0.05
        return -0.5 * np.sum(((y_obs - y_pred) / sigma) ** 2)
    except Exception:
        return -np.inf

# MCMC setup
np.random.seed(123)
n_steps = 1000
chain = np.zeros((n_steps, 2))
theta_curr = np.array([1.5, 0.5])
ll_curr = log_likelihood(theta_curr)

for i in range(n_steps):
    theta_prop = theta_curr + np.random.normal(0, 0.05, size=2)
    ll_prop = log_likelihood(theta_prop)

    if np.log(np.random.rand()) < ll_prop - ll_curr:
        theta_curr = theta_prop
        ll_curr = ll_prop

    chain[i] = theta_curr

with h5py.File('/home/user/posterior.h5', 'w') as f:
    f.create_dataset('chain', data=chain)
print(\"MCMC completed successfully.\")
\"\"\"

nb = new_notebook()
nb.cells.append(new_code_cell(nb_code))
with open('/home/user/mcmc_fit.ipynb', 'w') as f:
    nbformat.write(nb, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
