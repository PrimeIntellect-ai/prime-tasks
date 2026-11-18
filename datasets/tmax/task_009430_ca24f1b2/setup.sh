#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/optimization

    cat << 'EOF' > /home/user/optimization/helper.py
# Legacy dependency that is no longer installed
import obsolete_math_lib_v1

def log_result(val):
    with open("/home/user/optimization/root_result.txt", "w") as f:
        f.write(f"{val:.5f}\n")
EOF

    cat << 'EOF' > /home/user/optimization/find_root.py
import sys
from helper import log_result

def f(x):
    return x**3 - 2*x + 2

def df(x):
    return 3*x**2 - 2

def newton_raphson(initial_guess, max_iter=1000):
    x = initial_guess
    for _ in range(max_iter):
        fx = f(x)
        dfx = df(x)
        if abs(fx) < 1e-7:
            return x
        if dfx == 0:
            raise ValueError("Zero derivative")
        x = x - fx / dfx
    raise RuntimeError("Failed to converge")

if __name__ == "__main__":
    # Bug: This initial guess causes oscillation between 0 and 1
    x0 = 0.0
    root = newton_raphson(x0)
    log_result(root)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
