#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/analyze.py
import numpy as np
from scipy.optimize import root_scalar

def f_model(x):
    # Hidden true parameters
    x0 = 4.234567
    gamma = 0.001
    A = 1.5
    return A / (np.pi * gamma * (1.0 + ((x - x0) / gamma)**2))

def f_prime(x):
    x0 = 4.234567
    gamma = 0.001
    A = 1.5
    return -2.0 * A * (x - x0) / (np.pi * gamma**3 * (1.0 + ((x - x0) / gamma)**2)**2)

def adaptive_simpson(f, a, b, tol=1e-6):
    m = (a + b) / 2.0
    h = (b - a) / 2.0

    S_whole = (h / 3.0) * (f(a) + 4.0*f(m) + f(b))

    h_half = h / 2.0
    m1 = (a + m) / 2.0
    m2 = (m + b) / 2.0
    S_left = (h_half / 3.0) * (f(a) + 4.0*f(m1) + f(m))
    S_right = (h_half / 3.0) * (f(m) + 4.0*f(m2) + f(b))

    if abs(S_left + S_right - S_whole) < 15.0 * tol:
        return S_left + S_right + (S_left + S_right - S_whole) / 15.0
    else:
        return adaptive_simpson(f, a, m, tol/2.0) + adaptive_simpson(f, m, b, tol/2.0)

if __name__ == "__main__":
    # Naive integration attempt
    area = adaptive_simpson(f_model, 0.0, 10.0)
    print(f"Calculated Area: {area}")
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
