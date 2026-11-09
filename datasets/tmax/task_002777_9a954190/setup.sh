#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/vdp_mcmc.py
import numpy as np
import emcee

def vdp_deriv(t, y, mu):
    return [y[1], mu * (1 - y[0]**2) * y[1] - y[0]]

def simulate_vdp(mu):
    # Buggy fixed-step Euler integrator
    y = [2.0, 0.0]
    t = 0.0
    dt = 0.05
    for _ in range(200):
        dydt = vdp_deriv(t, y, mu)
        y[0] += dt * dydt[0]
        y[1] += dt * dydt[1]
        t += dt
        if abs(y[0]) > 100 or abs(y[1]) > 100:
            return None # Diverged
    return y[0]

def log_prior(mu):
    if 0.1 < mu[0] < 5.0:
        return 0.0
    return -np.inf

def log_likelihood(mu):
    final_y0 = simulate_vdp(mu[0])
    if final_y0 is None:
        return -np.inf
    # Target final state y[0] at t=10 to be around -1.5
    return -0.5 * ((final_y0 - (-1.5)) / 0.5)**2

def log_probability(mu):
    lp = log_prior(mu)
    if not np.isfinite(lp):
        return -np.inf
    return lp + log_likelihood(mu)

if __name__ == "__main__":
    np.random.seed(42)
    nwalkers = 10
    ndim = 1
    p0 = np.random.uniform(0.5, 1.0, (nwalkers, ndim))

    sampler = emcee.EnsembleSampler(nwalkers, ndim, log_probability)
    sampler.run_mcmc(p0, 500, progress=True)

    samples = sampler.get_chain(discard=100, flat=True)
    np.save("/home/user/valid_mu_samples.npy", samples)
EOF
    chmod +x /home/user/vdp_mcmc.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
