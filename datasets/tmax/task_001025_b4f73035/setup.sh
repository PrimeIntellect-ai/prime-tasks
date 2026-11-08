#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas emcee

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequence_data.csv
time,mutation_load
0,10.0
2,21.5
4,45.2
6,88.9
8,155.1
10,234.8
12,305.2
14,350.5
16,375.1
18,388.0
20,395.2
EOF

    cat << 'EOF' > /home/user/mcmc_mutations.py
import numpy as np
import pandas as pd
import emcee
import json

# Load data
data = pd.read_csv('/home/user/sequence_data.csv')
t_data = data['time'].values
y_data = data['mutation_load'].values

def solve_ode_euler(r, K, d, t_points):
    # DIVERGENT: Fixed-step Euler with too large a step size
    dt = 0.5 
    y = np.zeros(len(t_points))
    y[0] = 10.0 # Initial condition

    curr_y = y[0]
    curr_t = t_points[0]
    idx = 1

    while idx < len(t_points):
        while curr_t < t_points[idx]:
            # ODE: dy/dt = r*y*(1 - y/K) - d*y
            dy = (r * curr_y * (1.0 - curr_y / K) - d * curr_y) * dt
            curr_y += dy
            curr_t += dt
        y[idx] = curr_y
        idx += 1
    return y

def log_prior(theta):
    r, K, d = theta
    if 0.0 < r < 2.0 and 100.0 < K < 2000.0 and 0.0 < d < 1.0:
        return 0.0
    return -np.inf

def log_likelihood(theta):
    r, K, d = theta
    try:
        y_model = solve_ode_euler(r, K, d, t_data)
        if np.any(np.isnan(y_model)) or np.any(np.isinf(y_model)):
            return -np.inf
        sigma = 5.0
        return -0.5 * np.sum(((y_data - y_model) / sigma) ** 2)
    except:
        return -np.inf

def log_probability(theta):
    lp = log_prior(theta)
    if not np.isfinite(lp):
        return -np.inf
    return lp + log_likelihood(theta)

if __name__ == "__main__":
    nwalkers = 50
    ndim = 3

    # Initial guess around true values + noise
    np.random.seed(42)
    initial = np.array([0.4, 500.0, 0.1])
    pos = initial + 1e-4 * np.random.randn(nwalkers, ndim)

    # SEQUENTIAL SAMPLER (Slow, needs multiprocessing)
    sampler = emcee.EnsembleSampler(nwalkers, ndim, log_probability)

    print("Running MCMC...")
    sampler.run_mcmc(pos, 500, progress=True)

    samples = sampler.get_chain(discard=100, flat=True)
    r_m, K_m, d_m = np.mean(samples, axis=0)

    res = {
        "r_mean": round(float(r_m), 3),
        "K_mean": round(float(K_m), 3),
        "d_mean": round(float(d_m), 3)
    }

    with open('/home/user/posterior_summary.json', 'w') as f:
        json.dump(res, f, indent=2)
EOF

    chmod -R 777 /home/user
