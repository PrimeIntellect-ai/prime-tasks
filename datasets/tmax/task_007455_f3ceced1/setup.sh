#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user/kinetics

    cat << 'EOF' > /home/user/kinetics/reference.csv
time,B
0.0,0.000000
0.5,0.472367
1.0,0.364632
1.5,0.225576
2.0,0.130638
EOF

    cat << 'EOF' > /home/user/kinetics/fit_kinetics.py
import numpy as np
import pandas as pd
from scipy.optimize import minimize

# Load reference data
ref_data = pd.read_csv('/home/user/kinetics/reference.csv')
t_ref = ref_data['time'].values
B_ref = ref_data['B'].values

def euler_integrate(k1, k2, t_eval):
    """
    Integrates the system:
    dA/dt = -k1 * A
    dB/dt = k1 * A - k2 * B
    dC/dt = k2 * B
    """
    # BUG: step size is too large, leading to numerical instability during optimization
    dt = 0.5 

    A, B, C = 1.0, 0.0, 0.0
    t = 0.0

    results = {0.0: B}

    # Iterate to max time
    max_t = np.max(t_eval)
    while t < max_t:
        dA = -k1 * A
        dB = k1 * A - k2 * B

        A += dA * dt
        B += dB * dt
        t += dt

        # Store approximate values at evaluated time points
        for te in t_eval:
            if abs(t - te) < 1e-5:
                results[te] = B

    return np.array([results[te] for te in t_eval])

def objective(params):
    k1, k2 = params
    # TODO: Calculate simulated B over t_ref
    # TODO: Return Sum of Squared Errors (SSE) compared to B_ref
    return 1e9

if __name__ == "__main__":
    initial_guess = [1.0, 1.0]

    # TODO: Run scipy.optimize.minimize using Nelder-Mead

    # TODO: Write the optimized k1, k2 to /home/user/kinetics/optimal_params.txt
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
