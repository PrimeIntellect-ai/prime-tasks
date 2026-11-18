#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy setuptools

    # Create vendored package structure
    mkdir -p /app/adaptive_solve/adaptive_solve

    cat << 'EOF' > /app/adaptive_solve/setup.py
from setuptools import setup, find_packages

setup(
    name='adaptive_solve',
    version='0.1',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/adaptive_solve/adaptive_solve/__init__.py
from .integrator import integrate_logistic
EOF

    cat << 'EOF' > /app/adaptive_solve/adaptive_solve/integrator.py
def integrate_logistic(r, y0=0.5, t_end=10.0, tol=1e-5):
    t = 0.0
    y = y0
    h = 0.1
    steps = 0
    while t < t_end:
        if t + h > t_end:
            h = t_end - t
        k1 = r*y - y**2
        k2 = r*(y + h*k1/2) - (y + h*k1/2)**2
        k3 = r*(y + h*k2/2) - (y + h*k2/2)**2
        k4 = r*(y + h*k3) - (y + h*k3)**2
        y_next = y + h*(k1 + 2*k2 + 2*k3 + k4)/6.0

        y_euler = y + h*k1
        err = abs(y_next - y_euler) + 1e-15

        if err <= tol:
            t += h
            y = y_next
            steps += 1

        h = h * (err / tol)**0.5

        if h < 1e-5: h = 1e-5
        if h > 1.0: h = 1.0
        if steps > 100000:
            raise RuntimeError("Diverged")

    return y, steps
EOF

    # Create oracle directory and file
    mkdir -p /oracle
    cat << 'EOF' > /oracle/solve.py
import sys
import numpy as np

def lcs(X, Y):
    m = len(X)
    n = len(Y)
    L = [[0]*(n+1) for _ in range(m+1)]
    for i in range(m+1):
        for j in range(n+1):
            if i == 0 or j == 0 :
                L[i][j] = 0
            elif X[i-1] == Y[j-1]:
                L[i][j] = L[i-1][j-1]+1
            else:
                L[i][j] = max(L[i-1][j], L[i][j-1])
    return L[m][n]

def integrate_logistic(r, y0=0.5, t_end=10.0, tol=1e-5):
    t = 0.0
    y = y0
    h = 0.1
    steps = 0
    while t < t_end:
        if t + h > t_end:
            h = t_end - t
        k1 = r*y - y**2
        k2 = r*(y + h*k1/2) - (y + h*k1/2)**2
        k3 = r*(y + h*k2/2) - (y + h*k2/2)**2
        k4 = r*(y + h*k3) - (y + h*k3)**2
        y_next = y + h*(k1 + 2*k2 + 2*k3 + k4)/6.0

        y_euler = y + h*k1
        err = abs(y_next - y_euler) + 1e-15

        if err <= tol:
            t += h
            y = y_next
            steps += 1

        h = h * (tol / err)**0.5

        if h < 1e-5: h = 1e-5
        if h > 1.0: h = 1.0
        if steps > 100000:
            raise RuntimeError("Diverged")

    return y, steps

if __name__ == '__main__':
    seqs = sys.argv[1:]
    n = len(seqs)
    A = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            A[i,j] = lcs(seqs[i], seqs[j])

    U, S, Vh = np.linalg.svd(A)
    r = S[0]

    y, steps = integrate_logistic(r)
    print(f"y_final: {y:.6f}, steps: {steps}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
