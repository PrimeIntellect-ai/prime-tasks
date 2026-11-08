#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy flask fastapi uvicorn setuptools

    mkdir -p /app/mol_sim_net-1.0.0/mol_sim_net

    cat << 'EOF' > /app/mol_sim_net-1.0.0/setup.py
from setuptools import setup, find_packages
setup(
    name='mol_sim_net',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['numpy']
)
EOF

    cat << 'EOF' > /app/mol_sim_net-1.0.0/mol_sim_net/__init__.py
from .integrator import integrate_diffusion
EOF

    cat << 'EOF' > /app/mol_sim_net-1.0.0/mol_sim_net/integrator.py
import numpy as np

def integrate_diffusion(laplacian, x0, t_end, tol=1e-4):
    """
    Integrates dx/dt = -L x using an adaptive Heun-Euler method.
    """
    t = 0.0
    x = np.array(x0, dtype=float)
    dt = 0.1
    L = np.array(laplacian, dtype=float)

    while t < t_end:
        if t + dt > t_end:
            dt = t_end - t

        k1 = -L @ x
        x_euler = x + dt * k1

        k2 = -L @ x_euler
        x_heun = x + (dt / 2.0) * (k1 + k2)

        err = np.max(np.abs(x_heun - x_euler))
        if err == 0:
            err = 1e-16

        # BUG: The step size adaptation is inverted!
        dt_new = dt * (err / tol)**0.5

        # Guard against completely wild steps due to bug
        if dt_new > 5.0: dt_new = 5.0
        if dt_new < 1e-8: raise ValueError("Step size too small or diverged")

        if err <= tol:
            x = x_heun
            t += dt

        dt = dt_new

        if np.any(np.isnan(x)) or np.max(np.abs(x)) > 1e6:
            raise ValueError("Integration diverged")

    return x.tolist()
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
