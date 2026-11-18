#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest numpy

    mkdir -p /home/user/mcmc_project
    cat << 'EOF' > /home/user/mcmc_project/mcmc_integration.py
import numpy as np
import sys

# Deterministic seed based on time/run to simulate stochastic runs but keep it simple
# We'll use a random seed so runs produce different outputs
np.random.seed()

def run_mcmc():
    dim = 5
    # Simulate a near-singular covariance matrix
    cov = np.ones((dim, dim)) * 0.99 + np.eye(dim) * 0.0001

    # This will fail randomly or consistently without jitter
    # We force it to fail if jitter isn't added by making it strictly singular
    cov[:, 4] = cov[:, 0]
    cov[4, :] = cov[0, :]

    # Agent needs to add jitter before this line
    L = np.linalg.cholesky(cov)

    # Simulate integration result
    result = np.random.normal(loc=15.5, scale=2.1)
    return result

if __name__ == "__main__":
    try:
        val = run_mcmc()
        print(f"{val:.6f}")
    except np.linalg.LinAlgError:
        print("LinAlgError", file=sys.stderr)
        sys.exit(1)
EOF
    chmod +x /home/user/mcmc_project/mcmc_integration.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
