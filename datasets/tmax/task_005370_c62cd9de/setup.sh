#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/computation.py
import numpy as np
import time

def compute_log_sum_exp(x):
    # Naive implementation prone to overflow
    return np.log(np.sum(np.exp(x)))

def expensive_computation():
    np.random.seed(42)
    A = np.random.rand(2000, 2000)
    B = np.random.rand(2000, 2000)
    start = time.time()
    C = np.dot(A, B)
    end = time.time()
    return end - start
EOF

    cat << 'EOF' > /home/user/app/env.sh
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
