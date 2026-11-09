#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/optimization_lib/tests
touch /home/user/optimization_lib/__init__.py
touch /home/user/optimization_lib/tests/__init__.py

cat << 'EOF' > /home/user/optimization_lib/solver.py
class ConvergenceError(Exception):
    pass

def newton_root_finder(f, df, x0, tol=1e-5, max_iter=50):
    """
    Finds the root of a function using the Newton-Raphson method.
    Returns a tuple of (root, iterations_taken).
    """
    x = x0
    for i in range(max_iter):
        fx = f(x)
        if abs(fx) < tol:
            return x, i

        dfx = df(x)
        if dfx == 0:
            raise ConvergenceError("Derivative is zero.")

        # BUG: Incorrect sign in the Newton-Raphson update step.
        # It should be x = x - fx / dfx
        x = x + fx / dfx

    raise ConvergenceError(f"Failed to converge after {max_iter} iterations.")
EOF

cat << 'EOF' > /home/user/optimization_lib/tests/test_solver.py
from optimization_lib.solver import newton_root_finder, ConvergenceError

def test_cubic_root():
    # f(x) = x^3 - x - 2, root is approx 1.521
    f = lambda x: x**3 - x - 2
    df = lambda x: 3 * x**2 - 1
    root, iters = newton_root_finder(f, df, 2.0)
    assert abs(root**3 - root - 2) < 1e-4
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
