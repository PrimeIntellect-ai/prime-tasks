#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    python3 -c "
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

Ns = [10, 20, 40, 80]
for N in Ns:
    dt = 1.0 / N
    mean = 2.0 + 1.5 * dt
    std = 2.0 + 0.8 * dt
    samples = np.random.normal(mean, std, 10000)
    np.savetxt(f'/home/user/sim_{N}.txt', samples, fmt='%.6f')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
