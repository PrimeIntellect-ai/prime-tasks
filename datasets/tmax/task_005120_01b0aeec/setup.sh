#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/solver_repo
    cd /home/user/solver_repo
    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    cat << 'EOF' > requirements.txt
numpy==1.24.3
scipppy==1.10.1
EOF

    cat << 'EOF' > solver.py
import os
import sys

def f(x, c):
    return x**3 - 2*x + c

def df(x):
    return 3*x**2 - 2

def newton_raphson(c, x0=0.0, tol=1e-7, max_iter=50):
    x = x0
    for i in range(max_iter):
        fx = f(x, c)
        if abs(fx) < tol:
            return x
        dfx = df(x)
        if dfx == 0:
            raise RuntimeError("Derivative is zero.")
        x = x - fx / dfx
    raise RuntimeError(f"Failed to converge after {max_iter} iterations.")

if __name__ == "__main__":
    c = 2.0

    try:
        # Hardcoded initial guess x0=0.0 causes oscillation 0 -> 1 -> 0 -> 1 for c=2
        root = newton_raphson(c, x0=0.0)

        # Assertion-based intermediate validation
        assert abs(f(root, c)) < 1e-5, "Root validation failed!"
        print(f"Converged root: {root}")
    except Exception as e:
        print(f"Error during optimization: {e}")
        sys.exit(1)
EOF

    git add requirements.txt solver.py
    git commit -m "Initial commit with hardcoded calibration constant"

    cat << 'EOF' > solver.py
import os
import sys

def f(x, c):
    return x**3 - 2*x + c

def df(x):
    return 3*x**2 - 2

def newton_raphson(c, x0=0.0, tol=1e-7, max_iter=50):
    x = x0
    for i in range(max_iter):
        fx = f(x, c)
        if abs(fx) < tol:
            return x
        dfx = df(x)
        if dfx == 0:
            raise RuntimeError("Derivative is zero.")
        x = x - fx / dfx
    raise RuntimeError(f"Failed to converge after {max_iter} iterations.")

if __name__ == "__main__":
    # The constant must be fetched from the environment
    c_str = os.environ.get("CALIB_CONST")
    if not c_str:
        print("Error: CALIB_CONST environment variable missing.")
        sys.exit(1)

    c = float(c_str)

    try:
        # Hardcoded initial guess x0=0.0 causes oscillation 0 -> 1 -> 0 -> 1 for c=2
        root = newton_raphson(c, x0=0.0)

        # Assertion-based intermediate validation
        assert abs(f(root, c)) < 1e-5, "Root validation failed!"
        print(f"Converged root: {root}")
    except Exception as e:
        print(f"Error during optimization: {e}")
        sys.exit(1)
EOF

    git add solver.py
    git commit -m "Refactor: remove hardcoded calibration constant to env var"

    chmod -R 777 /home/user
