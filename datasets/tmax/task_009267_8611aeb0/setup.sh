#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# 1. Generate near-singular dataset
np.random.seed(10)
x1 = np.random.normal(0, 1, 100)
x2 = np.random.normal(0, 1, 100)
x3 = x1 + x2 # Perfect collinearity
data = np.vstack([x1, x2, x3]).T
np.save('/home/user/data.npy', data)

# 2. Create the buggy MCMC sampler
mcmc_code = """import numpy as np

def run_mcmc(data, iterations):
    np.random.seed(123)
    # Calculate empirical cov (singular)
    cov = np.cov(data, rowvar=False)

    # This will crash with singular matrix
    inv_cov = np.linalg.inv(cov)

    samples = []
    current_state = np.zeros(data.shape[1])
    accepted = 0

    # Simple random walk Metropolis-Hastings
    for _ in range(iterations):
        proposal = current_state + np.random.multivariate_normal(np.zeros(data.shape[1]), np.eye(data.shape[1])*0.1)

        # Log unnormalized posterior
        ll_prop = -0.5 * proposal.T @ inv_cov @ proposal
        ll_curr = -0.5 * current_state.T @ inv_cov @ current_state

        if np.log(np.random.rand()) < (ll_prop - ll_curr):
            current_state = proposal
            accepted += 1

        samples.append(current_state)

    return np.array(samples), accepted / iterations
"""

with open('/home/user/mcmc_sampler.py', 'w') as f:
    f.write(mcmc_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
