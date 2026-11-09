#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/requirements.txt
numpy>=1.20.0,<=1.21.0
pandas==2.2.0
pytest==7.4.3
EOF

    cat << 'EOF' > /home/user/project/optimize.py
import numpy as np

def f(x):
    return x**3 - 2*x + 2

def df(x):
    return 3*x**2 - 2

def optimize_function(initial_guess=0.0):
    # Newton's method
    x = initial_guess
    for _ in range(100):
        derivative = df(x)
        if derivative == 0:
            x += 0.01
            continue
        x_new = x - f(x)/derivative
        if abs(x_new - x) < 1e-6:
            return x_new
        x = x_new
    raise ValueError("Convergence failure: max iterations reached")

if __name__ == "__main__":
    print(optimize_function())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
