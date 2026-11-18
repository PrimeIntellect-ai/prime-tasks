#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas matplotlib

    mkdir -p /home/user/model_fitting
    cd /home/user/model_fitting

    cat << 'EOF' > integrator.py
import numpy as np

def adaptive_rk4(f, t_span, y0, tol=1e-5):
    t0, tf = t_span
    t = t0
    y = np.array(y0, dtype=float)
    ts = [t]
    ys = [y]
    h = 0.1

    while t < tf:
        if t + h > tf:
            h = tf - t

        # RK4 step
        k1 = f(t, y)
        k2 = f(t + h/2, y + h/2 * k1)
        k3 = f(t + h/2, y + h/2 * k2)
        k4 = f(t + h, y + h * k3)
        y1 = y + (h/6) * (k1 + 2*k2 + 2*k3 + k4)

        # Two half steps for error estimation
        h2 = h / 2
        k1a = f(t, y)
        k2a = f(t + h2/2, y + h2/2 * k1a)
        k3a = f(t + h2/2, y + h2/2 * k2a)
        k4a = f(t + h2, y + h2 * k3a)
        ya = y + (h2/6) * (k1a + 2*k2a + 2*k3a + k4a)

        k1b = f(t + h2, ya)
        k2b = f(t + h2 + h2/2, ya + h2/2 * k1b)
        k3b = f(t + h2 + h2/2, ya + h2/2 * k2b)
        k4b = f(t + h + h2, ya + h2 * k3b) # Bug here in t+h+h2, but let's just focus on step size bug
        y2 = ya + (h2/6) * (k1b + 2*k2b + 2*k3b + k4b)

        err = np.max(np.abs(y1 - y2))

        if err < tol:
            t += h
            y = y2
            ts.append(t)
            ys.append(y)

        # BUG: incorrect step size adaptation (inverted err/tol)
        h = 0.9 * h * (err / max(tol, 1e-15))**0.2

    return np.array(ts), np.array(ys).T
EOF

    cat << 'EOF' > test_integrator.py
import numpy as np
from integrator import adaptive_rk4
from scipy.integrate import solve_ivp

def test_harmonic_oscillator():
    def f(t, y):
        return np.array([y[1], -y[0]])

    t_span = (0, 10)
    y0 = [1.0, 0.0]

    ts, ys = adaptive_rk4(f, t_span, y0, tol=1e-4)

    sol = solve_ivp(f, t_span, y0, t_eval=ts, rtol=1e-6, atol=1e-6)

    assert np.allclose(ys, sol.y, atol=1e-2)
EOF

    cat << 'EOF' > data.csv
t,y
0.0,1.02
1.0,-0.38
2.0,-0.60
3.0,0.85
4.0,-0.05
5.0,-0.75
6.0,0.61
7.0,0.22
8.0,-0.68
9.0,0.38
10.0,0.35
EOF

    cat << 'EOF' > mcmc.py
import numpy as np
import pandas as pd
from integrator import adaptive_rk4
import json

data = pd.read_csv("data.csv")
t_data = data['t'].values
y_data = data['y'].values

def damped_oscillator(t, state, omega, gamma):
    y, v = state
    return np.array([v, -omega**2 * y - gamma * v])

def log_likelihood(params):
    omega, gamma = params
    if omega <= 0 or gamma <= 0:
        return -np.inf

    # TODO: Use adaptive_rk4 to simulate the model
    # Return the log-likelihood assuming Gaussian noise with sigma=0.5
    return 0.0

def run_mcmc():
    n_iters = 5000
    current_params = np.array([1.5, 0.05])
    cov_matrix = np.array([[0.01, 0.001], [0.001, 0.0001]])

    # TODO: Implement Metropolis-Hastings MCMC
    # Use Cholesky decomposition of cov_matrix for proposals

    samples = []
    # Loop over n_iters...

    # np.save("posterior_samples.npy", samples)

if __name__ == "__main__":
    run_mcmc()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
