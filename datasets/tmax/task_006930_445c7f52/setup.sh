#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/lorenz_ensemble.py
import numpy as np
import multiprocessing as mp
from scipy.integrate import solve_ivp
import pandas as pd

def lorenz(t, state, sigma=10.0, rho=28.0, beta=8.0/3.0):
    x, y, z = state
    dx = sigma * (y - x)
    dy = x * (rho - z) - y
    dz = x * y - beta * z
    return [dx, dy, dz]

def solve_particle(state0):
    sol = solve_ivp(lorenz, [0, 5], state0, t_eval=[5])
    return sol.y[:, 0]

if __name__ == '__main__':
    np.random.seed(42)
    N_particles = 100
    initial_states = np.random.rand(N_particles, 3) * 10

    with mp.Pool(4) as pool:
        # BUG: imap_unordered causes non-deterministic row order
        results = list(pool.imap_unordered(solve_particle, initial_states))

    df = pd.DataFrame(results, columns=['x', 'y', 'z'])
    df.to_csv('/home/user/training_data.csv', index=False)
EOF

    sed 's/imap_unordered/map/g' /home/user/lorenz_ensemble.py > /home/user/lorenz_ref.py
    python3 /home/user/lorenz_ref.py
    mv /home/user/training_data.csv /home/user/reference_data.csv
    rm /home/user/lorenz_ref.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
