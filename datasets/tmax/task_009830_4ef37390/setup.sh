#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/analysis

    # Create setup script to generate the numpy array
    cat << 'EOF' > /home/user/setup.py
import os
import numpy as np

os.makedirs('/home/user/analysis', exist_ok=True)
np.random.seed(42)
# Generate deterministic random start states
inputs = np.random.uniform(0, 1, (100, 500))
np.save('/home/user/analysis/input_profiles.npy', inputs)
EOF

    # Run setup script and clean it up
    python3 /home/user/setup.py
    rm /home/user/setup.py

    # Create the buggy script
    cat << 'EOF' > /home/user/analysis/sim_pop.py
import numpy as np
import json

def gene_dynamics(t, y):
    target = np.linspace(0, 1, len(y))
    return -50.0 * (y - target) + np.sin(t) * y

def simulate_profile(y0):
    t = 0.0
    t_end = 10.0
    y = y0.copy()
    dt = 0.5 # Too large for stiff system! Diverges.
    while t < t_end:
        y += dt * gene_dynamics(t, y)
        t += dt
    return y

if __name__ == "__main__":
    # TODO: Parallelize over 100 profiles from input_profiles.npy
    # Fix the integration to use scipy.integrate.solve_ivp with method='BDF'
    # Perform KDE estimation for the final states and save to final_metrics.json
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
