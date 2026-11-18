#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    cat << 'EOF' > /tmp/setup.py
import os
import h5py
import numpy as np
from scipy.integrate import solve_ivp

os.makedirs('/home/user/project', exist_ok=True)

# Generate true data
def true_system(t, state, c, k):
    x, v = state
    return [v, -c*v - k*x]

t_eval = np.linspace(0, 10, 50)
sol = solve_ivp(true_system, [0, 10], [1.0, 0.0], t_eval=t_eval, args=(0.5, 2.0))
np.random.seed(42)
noise = np.random.normal(0, 0.1, size=sol.y[0].shape)
y_obs = sol.y[0] + noise

with h5py.File('/home/user/project/data.h5', 'w') as f:
    f.create_dataset('t', data=t_eval)
    f.create_dataset('y', data=y_obs)

# Write buggy fit.py
script = '''import numpy as np
import h5py

# Load data (TODO: Make sure this works)
with h5py.File('data.h5', 'r') as f:
    t_obs = f['t'][:]
    y_obs = f['y'][:]

def solve_ode(c, k, t_eval):
    # Naive Euler method with dt=0.5 (diverges for stiffness of k=2)
    dt = 0.5
    x = 1.0
    v = 0.0
    y_sim = []

    current_time = 0.0
    idx = 0
    while idx < len(t_eval):
        if current_time >= t_eval[idx]:
            y_sim.append(x)
            idx += 1
            if idx == len(t_eval): break

        # Euler step
        x_next = x + dt * v
        v_next = v + dt * (-c*v - k*x)
        x = x_next
        v = v_next
        current_time += dt

    return np.array(y_sim)

def log_likelihood(c, k):
    if c <= 0 or k <= 0:
        return -np.inf
    y_sim = solve_ode(c, k, t_obs)
    # Assume sigma=0.1
    return -0.5 * np.sum(((y_obs - y_sim) / 0.1)**2)

# MCMC
np.random.seed(123)
c_current = 1.0
k_current = 1.0
ll_current = log_likelihood(c_current, k_current)

samples = []

for i in range(5000):
    c_prop = c_current + np.random.normal(0, 0.1)
    k_prop = k_current + np.random.normal(0, 0.1)

    ll_prop = log_likelihood(c_prop, k_prop)

    if np.log(np.random.uniform()) < ll_prop - ll_current:
        c_current = c_prop
        k_current = k_prop
        ll_current = ll_prop

    samples.append([c_current, k_current])

samples = np.array(samples)
'''
with open('/home/user/project/fit.py', 'w') as f:
    f.write(script)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
