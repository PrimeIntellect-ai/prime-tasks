#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mcmc_svd_target.py
import sys
import time
import numpy as np

def run_workload(seed):
    np.random.seed(seed)
    start = time.time()

    # SVD
    A = np.random.randn(150, 150)
    u, s, v = np.linalg.svd(A)

    # MCMC (Metropolis-Hastings)
    x = 0.0
    for _ in range(2000):
        cand = x + np.random.randn()
        if np.exp(-cand**2/2) / np.exp(-x**2/2) > np.random.rand():
            x = cand

    return time.time() - start

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    seed = int(sys.argv[1])
    # Sleep to ensure measurable, semi-consistent time base independent of CPU speed
    time.sleep(0.1 + (seed * 0.005))
    elapsed = run_workload(seed)
    print(f"{elapsed + 0.1 + (seed * 0.005):.4f}")
EOF
    chmod +x /home/user/mcmc_svd_target.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
