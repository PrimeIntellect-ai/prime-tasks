#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/simulation

    cat << 'EOF' > /home/user/simulation/poisson_matrix.py
import numpy as np
import scipy.linalg as la
import sys

def get_fourier_D2(N):
    """
    Build the second derivative matrix for a periodic domain [0, 2pi)
    using Fourier spectral collocation.
    """
    h = 2 * np.pi / N
    column = np.zeros(N)
    column[0] = -np.pi**2 / (3 * h**2) - 1.0 / 6.0
    for j in range(1, N):
        column[j] = -0.5 * (-1)**j / np.sin(j * h / 2)**2
    D2 = la.toeplitz(column)
    return D2

def main():
    if len(sys.argv) != 2:
        print("Usage: python poisson_matrix.py <N>")
        sys.exit(1)

    N = int(sys.argv[1])
    x = np.linspace(0, 2*np.pi, N, endpoint=False)

    # Right hand side: f(x) = sin(x) + cos(2x)
    # This integrates to 0 over [0, 2pi), so a solution exists.
    f = np.sin(x) + np.cos(2*x)

    D2 = get_fourier_D2(N)

    # THIS FAILS because D2 is singular
    u = np.linalg.solve(D2, f)

    # Output the maximum value of the solution
    print(np.max(u))

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/simulation/poisson_matrix.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
